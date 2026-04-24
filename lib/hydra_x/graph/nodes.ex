defmodule HydraX.Graph.Nodes do
  @moduledoc """
  CRUD and queries for `Graph.Node`. The single surface typed product
  contexts (`Insights`, `Decisions`, `Requirements`, etc.) will migrate
  onto as their underlying storage moves to the substrate.

  All query helpers accept a `project_id` — nodes are project-scoped by
  design; cross-project queries are an anti-pattern in V1.
  """

  import Ecto.Query, warn: false

  alias HydraX.Graph.Domain
  alias HydraX.Graph.Node
  alias HydraX.Repo

  @type project_scope :: integer()

  # Writes

  @doc """
  Create a node under the given domain/project/type. Defaults `scope`
  and `scope_root_id` to the project (matching the current platform
  convention). Attribute validation happens in `Node.changeset/2`
  against the declaring type's `attribute_schema`.
  """
  def create_node(%Domain{} = domain, project_id, attrs)
      when is_integer(project_id) and is_map(attrs) do
    base = %{
      domain_id: domain.id,
      project_id: project_id,
      scope: "project",
      scope_root_id: project_id
    }

    %Node{}
    |> Node.changeset(Map.merge(base, atomize(attrs)))
    |> Repo.insert()
  end

  def update_node(%Node{} = node, attrs) do
    node
    |> Node.transition_changeset(atomize(attrs))
    |> Repo.update()
  end

  def archive_node(%Node{} = node) do
    update_node(node, %{archived_at: DateTime.utc_now()})
  end

  # Reads

  def get_node(project_id, node_id) when is_integer(project_id) do
    Repo.get_by(Node, id: node_id, project_id: project_id)
  end

  def get_node!(project_id, node_id) when is_integer(project_id) do
    case get_node(project_id, node_id) do
      nil -> raise Ecto.NoResultsError, queryable: Node
      node -> node
    end
  end

  def list_nodes(project_id, opts \\ []) when is_integer(project_id) do
    include_archived = Keyword.get(opts, :include_archived, false)

    project_id
    |> base_query(include_archived)
    |> apply_filters(opts)
    |> apply_ordering(opts)
    |> Repo.all()
  end

  def list_by_type(project_id, type_key) when is_binary(type_key) do
    list_nodes(project_id, type_key: type_key)
  end

  def list_by_primitive(project_id, primitive) when is_binary(primitive) do
    list_nodes(project_id, extends_primitive: primitive)
  end

  # Internals

  defp base_query(project_id, true) do
    from n in Node, where: n.project_id == ^project_id
  end

  defp base_query(project_id, _include_archived) do
    from n in Node, where: n.project_id == ^project_id and is_nil(n.archived_at)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:type_key, key}, q when is_binary(key) ->
        from n in q, where: n.type_key == ^key

      {:extends_primitive, p}, q when is_binary(p) ->
        from n in q, where: n.extends_primitive == ^p

      {:status, s}, q when is_binary(s) ->
        from n in q, where: n.status == ^s

      _, q ->
        q
    end)
  end

  defp apply_ordering(query, opts) do
    case Keyword.get(opts, :order_by) do
      nil -> from n in query, order_by: [desc: n.inserted_at]
      :importance -> from n in query, order_by: [desc_nulls_last: n.importance]
      :updated -> from n in query, order_by: [desc: n.updated_at]
      _ -> query
    end
  end

  # Support both atom- and string-keyed attrs at the context boundary.
  # Ecto cast handles either, but normalising here keeps the changeset
  # logic simpler and avoids accidental merge-key mismatches.
  defp atomize(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {safe_atom(k), v}
    end)
  end

  @known_keys ~w(
    domain_id project_id type_key extends_primitive title body attributes
    status importance confidence scope scope_root_id lock_version
    created_by_agent_id created_by_operator archived_at
  )a
  @known_key_strings Enum.map(@known_keys, &Atom.to_string/1)

  defp safe_atom(key) do
    if key in @known_key_strings do
      String.to_existing_atom(key)
    else
      key
    end
  end
end
