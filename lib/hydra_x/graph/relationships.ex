defmodule HydraX.Graph.Relationships do
  @moduledoc """
  Edges between `Graph.Node`s. Replaces `product_graph_edges`. All
  functions are project-scoped and primitive-aware — `list_by_primitive/3`
  exists so engine behaviours (lineage traversal, coherence detection)
  can query without knowing about domain-specific type keys.
  """

  import Ecto.Query, warn: false

  alias HydraX.Graph.Domain
  alias HydraX.Graph.Node
  alias HydraX.Graph.NodeRelationship
  alias HydraX.Repo

  # Writes

  def create_relationship(
        %Domain{} = domain,
        %Node{} = from,
        %Node{} = to,
        type_key,
        attrs \\ %{}
      )
      when is_binary(type_key) do
    if from.project_id != to.project_id do
      {:error, :cross_project_relationship}
    else
      base = %{
        domain_id: domain.id,
        project_id: from.project_id,
        type_key: type_key,
        from_node_id: from.id,
        to_node_id: to.id
      }

      %NodeRelationship{}
      |> NodeRelationship.changeset(Map.merge(base, atomize(attrs)))
      |> Repo.insert()
    end
  end

  def delete_relationship(%NodeRelationship{} = rel), do: Repo.delete(rel)

  # Reads

  def list_outgoing(%Node{} = node, opts \\ []) do
    node.id
    |> outgoing_query()
    |> apply_filters(opts)
    |> Repo.all()
  end

  def list_incoming(%Node{} = node, opts \\ []) do
    node.id
    |> incoming_query()
    |> apply_filters(opts)
    |> Repo.all()
  end

  def neighbors(%Node{} = node, opts \\ []) do
    list_outgoing(node, opts) ++ list_incoming(node, opts)
  end

  @doc """
  List all relationships in a project whose `extends_primitive` matches.
  Used by domain-neutral engine behaviours.
  """
  def list_by_primitive(project_id, primitive, opts \\ [])
      when is_integer(project_id) and is_binary(primitive) do
    from(r in NodeRelationship,
      where: r.project_id == ^project_id and r.extends_primitive == ^primitive
    )
    |> apply_filters(opts)
    |> Repo.all()
  end

  def orphan?(%Node{} = node) do
    outgoing = Repo.aggregate(outgoing_query(node.id), :count, :id)
    incoming = Repo.aggregate(incoming_query(node.id), :count, :id)
    outgoing + incoming == 0
  end

  # Internals

  defp outgoing_query(node_id) do
    from r in NodeRelationship, where: r.from_node_id == ^node_id
  end

  defp incoming_query(node_id) do
    from r in NodeRelationship, where: r.to_node_id == ^node_id
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:type_key, key}, q when is_binary(key) ->
        from r in q, where: r.type_key == ^key

      {:extends_primitive, p}, q when is_binary(p) ->
        from r in q, where: r.extends_primitive == ^p

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
    domain_id project_id type_key extends_primitive from_node_id to_node_id
    weight attributes created_by_agent_id
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
