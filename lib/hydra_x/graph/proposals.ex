defmodule HydraX.Graph.Proposals do
  @moduledoc """
  Schema-change proposal lifecycle (spec §8). Agents and operators
  propose changes to a project's schema (add a node type, extend an
  attribute schema, add a relationship or flag type). Operators
  approve or reject; on approval, the substrate applies the change
  atomically and broadcasts a cache invalidation for that project.

  Per the Part 1 amendment, schemas are project-scoped — there is no
  global domain version to bump. Each project's "schema version" is
  implicit in the set of approved proposals it has applied.

  V1 is additive-only — removing or renaming types, changing attribute
  types, or deleting statuses is deferred. `apply_change/2` rejects
  anything outside the supported set.
  """

  import Ecto.Query, warn: false

  alias HydraX.Graph.ProjectSchemas
  alias HydraX.Graph.SchemaChangeProposal
  alias HydraX.Repo

  @pubsub_topic "graph:schema"

  @supported_kinds ~w(add_node_type add_relationship_type add_flag_type extend_node_type)

  @doc """
  Create a schema-change proposal in the `pending` state.

  `change_kind` must be one of #{inspect(@supported_kinds)}.
  `payload` is a map — its shape depends on the change_kind:

    * `add_node_type` — the same attrs you'd pass to
      `ProjectSchemas.upsert_node_type/2` (type_key, display_name, extends,
      attribute_schema, etc.).
    * `add_relationship_type` — attrs for `upsert_relationship_type/2`.
    * `add_flag_type` — attrs for `upsert_flag_type/2`.
    * `extend_node_type` — `%{"type_key" => "insight",
      "properties" => %{...}}` — new JSON Schema `properties` to merge
      into the existing type's `attribute_schema`.
  """
  def propose(project_id, change_kind, payload, attrs \\ %{})
      when is_integer(project_id) and is_binary(change_kind) and is_map(payload) do
    base = %{
      project_id: project_id,
      change_kind: change_kind,
      payload: stringify_keys(payload),
      status: "pending",
      rationale: Map.get(attrs, :rationale) || Map.get(attrs, "rationale"),
      proposed_by_agent_id:
        Map.get(attrs, :proposed_by_agent_id) || Map.get(attrs, "proposed_by_agent_id"),
      proposed_by_operator:
        Map.get(attrs, :proposed_by_operator, Map.get(attrs, "proposed_by_operator", false))
    }

    %SchemaChangeProposal{}
    |> SchemaChangeProposal.changeset(base)
    |> Repo.insert()
  end

  def list_proposals(project_id, opts \\ []) when is_integer(project_id) do
    status = Keyword.get(opts, :status)

    query =
      from(p in SchemaChangeProposal,
        where: p.project_id == ^project_id,
        order_by: [desc: p.inserted_at]
      )

    query =
      if is_nil(status), do: query, else: where(query, [p], p.status == ^to_string(status))

    Repo.all(query)
  end

  def get_proposal!(id), do: Repo.get!(SchemaChangeProposal, id)

  @doc """
  Approve a proposal. Applies the change in a transaction, records
  `applied_at`, flips status to `approved`, and broadcasts PubSub so
  live registries reload the project's schema.

  Returns `{:ok, %SchemaChangeProposal{}}` on success or
  `{:error, reason}` if the change cannot be applied.
  """
  def approve(proposal, opts \\ [])

  def approve(%SchemaChangeProposal{status: "pending"} = proposal, opts) do
    reviewed_by_operator = Keyword.get(opts, :by_operator, false)
    project_id = proposal.project_id

    Repo.transaction(fn ->
      case apply_change(project_id, proposal) do
        {:ok, _applied} ->
          {:ok, updated_proposal} =
            proposal
            |> SchemaChangeProposal.changeset(%{
              status: "approved",
              applied_at: DateTime.utc_now(),
              reviewed_by_operator: reviewed_by_operator
            })
            |> Repo.update()

          Phoenix.PubSub.broadcast(
            HydraX.PubSub,
            @pubsub_topic,
            {:schema_updated, project_id}
          )

          updated_proposal

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def approve(%SchemaChangeProposal{}, _opts), do: {:error, :not_pending}

  @doc """
  Reject a proposal. Records who reviewed it but does not apply the
  change.
  """
  def reject(proposal, opts \\ [])

  def reject(%SchemaChangeProposal{status: "pending"} = proposal, opts) do
    reviewed_by_operator = Keyword.get(opts, :by_operator, false)

    proposal
    |> SchemaChangeProposal.changeset(%{
      status: "rejected",
      reviewed_by_operator: reviewed_by_operator
    })
    |> Repo.update()
  end

  def reject(%SchemaChangeProposal{}, _opts), do: {:error, :not_pending}

  # ---- Apply dispatch --------------------------------------------------

  defp apply_change(project_id, %SchemaChangeProposal{
         change_kind: "add_node_type",
         payload: payload
       }) do
    ProjectSchemas.upsert_node_type(project_id, atomize_attrs(payload))
  end

  defp apply_change(project_id, %SchemaChangeProposal{
         change_kind: "add_relationship_type",
         payload: payload
       }) do
    ProjectSchemas.upsert_relationship_type(project_id, atomize_attrs(payload))
  end

  defp apply_change(project_id, %SchemaChangeProposal{
         change_kind: "add_flag_type",
         payload: payload
       }) do
    ProjectSchemas.upsert_flag_type(project_id, atomize_attrs(payload))
  end

  defp apply_change(project_id, %SchemaChangeProposal{
         change_kind: "extend_node_type",
         payload: payload
       }) do
    type_key = Map.get(payload, "type_key")
    new_properties = Map.get(payload, "properties", %{})

    case ProjectSchemas.list_node_types(project_id)
         |> Enum.find(fn t -> t.type_key == type_key end) do
      nil ->
        {:error, :unknown_type_key}

      existing ->
        existing_schema = existing.attribute_schema || %{}
        existing_props = Map.get(existing_schema, "properties", %{})
        merged_props = Map.merge(existing_props, new_properties)
        merged_schema = Map.put(existing_schema, "properties", merged_props)

        ProjectSchemas.upsert_node_type(project_id, %{
          type_key: type_key,
          display_name: existing.display_name,
          description: existing.description,
          extends: existing.extends,
          status_vocabulary: existing.status_vocabulary,
          promotion_sources: existing.promotion_sources,
          icon: existing.icon,
          color_token: existing.color_token,
          version: (existing.version || 1) + 1,
          attribute_schema: merged_schema
        })
    end
  end

  defp apply_change(_project_id, %SchemaChangeProposal{change_kind: kind}) do
    {:error, {:unsupported_kind, kind}}
  end

  # ---- Helpers ---------------------------------------------------------

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp atomize_attrs(payload) when is_map(payload) do
    Map.new(payload, fn
      {k, v} when is_binary(k) ->
        case known_key_atom(k) do
          nil -> {k, v}
          atom -> {atom, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  @known_keys ~w(
    type_key display_name description extends attribute_schema
    status_vocabulary promotion_sources icon color_token version
    valid_from_types valid_to_types cardinality directional
    default_severity
  )a
  @known_key_strings Enum.map(@known_keys, &Atom.to_string/1)

  defp known_key_atom(key) do
    if key in @known_key_strings do
      String.to_existing_atom(key)
    else
      nil
    end
  end

  @doc false
  def supported_kinds, do: @supported_kinds
end
