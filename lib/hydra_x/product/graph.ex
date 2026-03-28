defmodule HydraX.Product.Graph do
  @moduledoc """
  Graph-level operations across all product node types: creating typed edges,
  traversing upstream/downstream chains, impact analysis, orphan detection, and
  density metrics.
  """

  import Ecto.Query

  alias HydraX.Product.ArchitectureNode
  alias HydraX.Product.Constraint
  alias HydraX.Product.Decision
  alias HydraX.Product.DesignNode
  alias HydraX.Product.GraphEdge
  alias HydraX.Product.GraphFlag
  alias HydraX.Product.Insight
  alias HydraX.Product.KnowledgeEntry
  alias HydraX.Product.Learning
  alias HydraX.Product.Requirement
  alias HydraX.Product.Routine
  alias HydraX.Product.Source
  alias HydraX.Product.Strategy
  alias HydraX.Product.Task, as: ProductTask
  alias HydraX.Repo

  @node_type_to_schema %{
    "signal" => Source,
    "source" => Source,
    "insight" => Insight,
    "decision" => Decision,
    "strategy" => Strategy,
    "requirement" => Requirement,
    "design_node" => DesignNode,
    "architecture_node" => ArchitectureNode,
    "task" => ProductTask,
    "learning" => Learning,
    "constraint" => Constraint,
    "routine" => Routine,
    "knowledge_entry" => KnowledgeEntry
  }

  @traversable_node_types Map.keys(@node_type_to_schema)

  @default_max_depth 10

  # -------------------------------------------------------------------
  # Edge operations
  # -------------------------------------------------------------------

  def link_nodes(project_id, from_type, from_id, to_type, to_id, kind, opts \\ []) do
    attrs = %{
      "project_id" => project_id,
      "from_node_type" => to_string(from_type),
      "from_node_id" => from_id,
      "to_node_type" => to_string(to_type),
      "to_node_id" => to_id,
      "kind" => to_string(kind),
      "weight" => Keyword.get(opts, :weight, 1.0),
      "metadata" => Keyword.get(opts, :metadata, %{})
    }

    %GraphEdge{}
    |> GraphEdge.changeset(attrs)
    |> Repo.insert()
  end

  def unlink_nodes(project_id, from_type, from_id, to_type, to_id, kind) do
    query =
      GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and
          e.from_node_type == ^to_string(from_type) and
          e.from_node_id == ^from_id and
          e.to_node_type == ^to_string(to_type) and
          e.to_node_id == ^to_id and
          e.kind == ^to_string(kind)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      edge -> Repo.delete(edge)
    end
  end

  def edges_from(project_id, node_type, node_id, opts \\ []) do
    kind = Keyword.get(opts, :kind)

    GraphEdge
    |> where(
      [e],
      e.project_id == ^project_id and
        e.from_node_type == ^to_string(node_type) and
        e.from_node_id == ^node_id
    )
    |> maybe_filter_kind(kind)
    |> Repo.all()
  end

  def edges_to(project_id, node_type, node_id, opts \\ []) do
    kind = Keyword.get(opts, :kind)

    GraphEdge
    |> where(
      [e],
      e.project_id == ^project_id and
        e.to_node_type == ^to_string(node_type) and
        e.to_node_id == ^node_id
    )
    |> maybe_filter_kind(kind)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Traversal
  # -------------------------------------------------------------------

  def trace_upstream(project_id, node_type, node_id, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    kinds_filter = Keyword.get(opts, :kinds)

    do_trace(project_id, node_type, node_id, :upstream, max_depth, kinds_filter, MapSet.new())
  end

  def trace_downstream(project_id, node_type, node_id, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    kinds_filter = Keyword.get(opts, :kinds)

    do_trace(project_id, node_type, node_id, :downstream, max_depth, kinds_filter, MapSet.new())
  end

  defp do_trace(_project_id, _node_type, _node_id, _direction, 0, _kinds, _visited), do: []

  defp do_trace(project_id, node_type, node_id, direction, depth, kinds, visited) do
    key = {node_type, node_id}
    if MapSet.member?(visited, key), do: throw(:cycle)

    visited = MapSet.put(visited, key)

    edges =
      case direction do
        :upstream -> edges_to(project_id, node_type, node_id, kind_opts(kinds))
        :downstream -> edges_from(project_id, node_type, node_id, kind_opts(kinds))
      end

    neighbors =
      Enum.map(edges, fn edge ->
        case direction do
          :upstream -> {edge.from_node_type, edge.from_node_id, edge.kind}
          :downstream -> {edge.to_node_type, edge.to_node_id, edge.kind}
        end
      end)

    Enum.flat_map(neighbors, fn {neighbor_type, neighbor_id, edge_kind} ->
      children =
        try do
          do_trace(project_id, neighbor_type, neighbor_id, direction, depth - 1, kinds, visited)
        catch
          :cycle -> []
        end

      [%{node_type: neighbor_type, node_id: neighbor_id, edge_kind: edge_kind} | children]
    end)
  end

  defp kind_opts(nil), do: []
  defp kind_opts(kinds) when is_list(kinds), do: [kind: kinds]
  defp kind_opts(kind), do: [kind: kind]

  defp maybe_filter_kind(query, nil), do: query

  defp maybe_filter_kind(query, kinds) when is_list(kinds) do
    string_kinds = Enum.map(kinds, &to_string/1)
    where(query, [e], e.kind in ^string_kinds)
  end

  defp maybe_filter_kind(query, kind) do
    where(query, [e], e.kind == ^to_string(kind))
  end

  # -------------------------------------------------------------------
  # Impact analysis
  # -------------------------------------------------------------------

  def impact_of_change(project_id, node_type, node_id) do
    affected = trace_downstream(project_id, node_type, node_id)

    %{
      affected: Enum.map(affected, fn a -> {a.node_type, a.node_id, a.edge_kind} end),
      count: length(affected)
    }
  end

  # -------------------------------------------------------------------
  # Node resolution
  # -------------------------------------------------------------------

  def resolve_node(node_type, node_id) do
    case schema_for(node_type) do
      nil -> {:error, :unknown_node_type}
      schema -> {:ok, Repo.get(schema, node_id)}
    end
  end

  def resolve_nodes(type_id_pairs) do
    type_id_pairs
    |> Enum.group_by(fn {type, _id} -> type end, fn {_type, id} -> id end)
    |> Enum.flat_map(fn {type, ids} ->
      case schema_for(type) do
        nil ->
          []

        schema ->
          schema
          |> where([r], r.id in ^ids)
          |> Repo.all()
          |> Enum.map(fn record -> {type, record.id, record} end)
      end
    end)
  end

  def schema_for(node_type), do: Map.get(@node_type_to_schema, to_string(node_type))

  def node_types, do: @traversable_node_types

  # -------------------------------------------------------------------
  # Health checks
  # -------------------------------------------------------------------

  def orphaned_nodes(project_id, node_type \\ nil) do
    types =
      if node_type,
        do: [to_string(node_type)],
        else: @traversable_node_types -- ["signal", "source"]

    Enum.flat_map(types, fn type ->
      case schema_for(type) do
        nil ->
          []

        schema ->
          node_ids_with_incoming =
            GraphEdge
            |> where([e], e.project_id == ^project_id and e.to_node_type == ^type)
            |> select([e], e.to_node_id)
            |> Repo.all()
            |> MapSet.new()

          all_nodes =
            schema
            |> where([r], r.project_id == ^project_id)
            |> select([r], {r.id, r.title})
            |> Repo.all()

          all_nodes
          |> Enum.reject(fn {id, _title} -> MapSet.member?(node_ids_with_incoming, id) end)
          |> Enum.map(fn {id, title} -> %{node_type: type, node_id: id, title: title} end)
      end
    end)
  end

  def density_report(project_id) do
    types = @traversable_node_types -- ["signal", "source"]

    Enum.into(types, %{}, fn type ->
      count =
        case schema_for(type) do
          nil -> 0
          schema -> schema |> where([r], r.project_id == ^project_id) |> Repo.aggregate(:count)
        end

      outgoing =
        GraphEdge
        |> where([e], e.project_id == ^project_id and e.from_node_type == ^type)
        |> Repo.aggregate(:count)

      avg_outgoing = if count > 0, do: outgoing / count, else: 0.0

      {type, %{count: count, outgoing: outgoing, avg_outgoing: Float.round(avg_outgoing, 2)}}
    end)
  end

  def stale_nodes(project_id, opts \\ []) do
    days = Keyword.get(opts, :days, 90)
    node_types_filter = Keyword.get(opts, :node_types)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400)

    types =
      if node_types_filter,
        do: Enum.map(node_types_filter, &to_string/1),
        else: @traversable_node_types -- ["signal", "source"]

    Enum.flat_map(types, fn type ->
      case schema_for(type) do
        nil ->
          []

        schema ->
          schema
          |> where([r], r.project_id == ^project_id and r.updated_at < ^cutoff)
          |> select([r], {r.id, r.title, r.updated_at})
          |> Repo.all()
          |> Enum.map(fn {id, title, updated_at} ->
            %{node_type: type, node_id: id, title: title, updated_at: updated_at}
          end)
      end
    end)
  end

  # -------------------------------------------------------------------
  # Flagging
  # -------------------------------------------------------------------

  def flag_node(project_id, node_type, node_id, flag_type, reason, agent \\ "system") do
    %GraphFlag{}
    |> GraphFlag.changeset(%{
      "project_id" => project_id,
      "node_type" => to_string(node_type),
      "node_id" => node_id,
      "flag_type" => to_string(flag_type),
      "reason" => reason,
      "source_agent" => agent,
      "status" => "open"
    })
    |> Repo.insert()
  end

  def resolve_flag(flag_id, resolved_by) do
    flag = Repo.get!(GraphFlag, flag_id)

    flag
    |> GraphFlag.changeset(%{
      "status" => "resolved",
      "resolved_by" => resolved_by,
      "resolved_at" => DateTime.utc_now()
    })
    |> Repo.update()
  end

  def open_flags(project_id, opts \\ []) do
    node_type = Keyword.get(opts, :node_type)
    flag_type = Keyword.get(opts, :flag_type)

    GraphFlag
    |> where([f], f.project_id == ^project_id and f.status == "open")
    |> maybe_filter_flag_node_type(node_type)
    |> maybe_filter_flag_type(flag_type)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_flag_node_type(query, nil), do: query

  defp maybe_filter_flag_node_type(query, node_type) do
    where(query, [f], f.node_type == ^to_string(node_type))
  end

  defp maybe_filter_flag_type(query, nil), do: query

  defp maybe_filter_flag_type(query, flag_type) do
    where(query, [f], f.flag_type == ^to_string(flag_type))
  end
end
