defmodule HydraX.Graph.Flags do
  @moduledoc """
  Coherence / quality signals attached to nodes. Replaces the typed
  `graph_flags` table. Flag types are declared per-project via
  `FlagTypeDefinition`; raising an unknown flag is rejected.
  """

  import Ecto.Query, warn: false

  alias HydraX.Graph.Node
  alias HydraX.Graph.NodeFlag
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.Repo

  @doc """
  Raise a flag on a node. If the flag type is unknown for the node's
  project, returns `{:error, :unknown_flag_type}`. Severity defaults
  to the type's `default_severity` if not specified.
  """
  def raise_flag(%Node{} = node, flag_type_key, attrs \\ %{})
      when is_binary(flag_type_key) do
    case SchemaRegistry.fetch_flag_type(node.project_id, flag_type_key) do
      :error ->
        {:error, :unknown_flag_type}

      {:ok, type_def} ->
        merged =
          %{
            node_id: node.id,
            flag_type_key: flag_type_key,
            severity: type_def.default_severity
          }
          |> Map.merge(atomize(attrs))

        %NodeFlag{}
        |> NodeFlag.changeset(merged)
        |> Repo.insert()
    end
  end

  def resolve_flag(%NodeFlag{} = flag, opts \\ []) do
    attrs = %{
      resolved_at: DateTime.utc_now(),
      resolved_by_operator: Keyword.get(opts, :by_operator, false)
    }

    flag
    |> NodeFlag.resolve_changeset(attrs)
    |> Repo.update()
  end

  def list_flags(%Node{} = node, opts \\ []) do
    node.id
    |> base_query()
    |> apply_filters(opts)
    |> Repo.all()
  end

  def open_flags(%Node{} = node) do
    list_flags(node, only_open: true)
  end

  defp base_query(node_id) do
    from f in NodeFlag, where: f.node_id == ^node_id
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:flag_type_key, key}, q when is_binary(key) ->
        from f in q, where: f.flag_type_key == ^key

      {:only_open, true}, q ->
        from f in q, where: is_nil(f.resolved_at)

      {:severity, sev}, q when is_binary(sev) ->
        from f in q, where: f.severity == ^sev

      _, q ->
        q
    end)
  end

  defp atomize(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {safe_atom(k), v}
    end)
  end

  @known_keys ~w(
    node_id flag_type_key severity detected_by_agent_id detection_context
    resolved_at resolved_by_operator
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
