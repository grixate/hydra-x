defmodule HydraX.Product.Graph do
  @moduledoc """
  Graph-level operations across all product node types: creating typed edges,
  traversing upstream/downstream chains, impact analysis, orphan detection, and
  density metrics.
  """

  import Ecto.Query

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Graph.NodeRelationship
  alias HydraX.Product.GraphFlag
  alias HydraX.Repo

  @node_type_to_schema %{
    "signal" => GraphNode,
    "source" => GraphNode,
    "insight" => GraphNode,
    "decision" => GraphNode,
    "strategy" => GraphNode,
    "requirement" => GraphNode,
    "design_node" => GraphNode,
    "architecture_node" => GraphNode,
    "task" => GraphNode,
    "learning" => GraphNode,
    "constraint" => GraphNode,
    "routine" => GraphNode,
    "knowledge_entry" => GraphNode
  }

  @traversable_node_types Map.keys(@node_type_to_schema)

  @default_max_depth 10

  # -------------------------------------------------------------------
  # Edge operations
  # -------------------------------------------------------------------

  @doc """
  Create an edge between two nodes. Endpoint (type, id) pairs remain
  in the call signature for caller compatibility; storage routes to
  `node_relationships`.

  The edge's `type_key` (relationship type) equals the former `kind`.
  `metadata` becomes `attributes`. `from_node_type`/`to_node_type` are
  denormalized on the row so readers can filter without a join.
  """
  def link_nodes(project_id, from_type, from_id, to_type, to_id, kind, opts \\ []) do
    attrs = %{
      project_id: project_id,
      type_key: to_string(kind),
      from_node_id: from_id,
      to_node_id: to_id,
      from_node_type: substrate_type_for(from_type),
      to_node_type: substrate_type_for(to_type),
      weight: Keyword.get(opts, :weight, 1.0),
      attributes: Keyword.get(opts, :metadata, %{})
    }

    %NodeRelationship{}
    |> NodeRelationship.changeset(attrs)
    |> Repo.insert()
  end

  def unlink_nodes(project_id, from_type, from_id, to_type, to_id, kind) do
    query =
      from(r in NodeRelationship,
        where:
          r.project_id == ^project_id and
            r.from_node_type == ^substrate_type_for(from_type) and
            r.from_node_id == ^from_id and
            r.to_node_type == ^substrate_type_for(to_type) and
            r.to_node_id == ^to_id and
            r.type_key == ^to_string(kind)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      edge -> Repo.delete(edge)
    end
  end

  def edges_from(project_id, node_type, node_id, opts \\ []) do
    kind = Keyword.get(opts, :kind)

    from(r in NodeRelationship,
      where:
        r.project_id == ^project_id and
          r.from_node_type == ^substrate_type_for(node_type) and
          r.from_node_id == ^node_id
    )
    |> maybe_filter_kind(kind)
    |> Repo.all()
    |> Enum.map(&edge_facade/1)
  end

  def edges_to(project_id, node_type, node_id, opts \\ []) do
    kind = Keyword.get(opts, :kind)

    from(r in NodeRelationship,
      where:
        r.project_id == ^project_id and
          r.to_node_type == ^substrate_type_for(node_type) and
          r.to_node_id == ^node_id
    )
    |> maybe_filter_kind(kind)
    |> Repo.all()
    |> Enum.map(&edge_facade/1)
  end

  # Return a map with the legacy edge-shape field names so readers
  # that expect `.kind`, `.metadata` keep working while we finish the
  # shape-migration.
  defp edge_facade(%NodeRelationship{} = r) do
    %{
      id: r.id,
      project_id: r.project_id,
      from_node_type: r.from_node_type,
      from_node_id: r.from_node_id,
      to_node_type: r.to_node_type,
      to_node_id: r.to_node_id,
      kind: r.type_key,
      weight: r.weight,
      metadata: r.attributes || %{},
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
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
    where(query, [r], r.type_key in ^string_kinds)
  end

  defp maybe_filter_kind(query, kind) do
    where(query, [r], r.type_key == ^to_string(kind))
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
      GraphNode -> {:ok, fetch_substrate_node(node_type, node_id)}
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

        GraphNode ->
          substrate_type = substrate_type_for(type)

          GraphNode
          |> where([n], n.id in ^ids and n.type_key == ^substrate_type)
          |> Repo.all()
          |> Enum.map(fn record -> {type, record.id, record} end)

        schema ->
          schema
          |> where([r], r.id in ^ids)
          |> Repo.all()
          |> Enum.map(fn record -> {type, record.id, record} end)
      end
    end)
  end

  defp fetch_substrate_node(node_type, node_id) do
    substrate_type = substrate_type_for(node_type)

    Repo.one(
      from n in GraphNode,
        where: n.id == ^node_id and n.type_key == ^substrate_type
    )
  end

  def schema_for(node_type), do: Map.get(@node_type_to_schema, to_string(node_type))

  @doc """
  Base query for a node type. Returns an Ecto queryable that already
  filters by `type_key` for substrate-backed types (the `nodes` table
  stores many types side-by-side), or the typed schema module unchanged
  for legacy types.
  """
  def base_query_for(node_type) do
    type_str = to_string(node_type)

    case schema_for(type_str) do
      nil ->
        nil

      GraphNode ->
        # "signal" is a legacy alias for the "source" type_key.
        substrate_type = if type_str == "signal", do: "source", else: type_str
        from(n in GraphNode, where: n.type_key == ^substrate_type)

      schema ->
        schema
    end
  end

  def node_types, do: @traversable_node_types

  # "signal" is a legacy display-layer alias for "source" — the
  # substrate stores both as type_key="source".
  defp substrate_type_for(type) do
    case to_string(type) do
      "signal" -> "source"
      other -> other
    end
  end

  # -------------------------------------------------------------------
  # Health checks
  # -------------------------------------------------------------------

  def orphaned_nodes(project_id, node_type \\ nil) do
    types =
      if node_type,
        do: [to_string(node_type)],
        else: @traversable_node_types -- ["signal", "source"]

    # Primitive-keyed path: any substrate node whose primitive is one
    # that *should* participate in the graph. Evidence-extending nodes
    # (like sources) can reasonably be dangling; exclude them.
    substrate_orphans =
      if node_type do
        substrate_orphans_for_type(project_id, to_string(node_type))
      else
        substrate_orphans_for_primitives(project_id, ~w(claim entity artifact activity))
      end

    # Legacy-typed node orphans (vision, etc.) — keep the per-type loop
    # until those schemas also move onto the substrate.
    legacy_types =
      types
      |> Enum.reject(fn t -> substrate_type?(t) end)

    legacy_orphans =
      Enum.flat_map(legacy_types, fn type ->
        case base_query_for(type) do
          nil ->
            []

          query ->
            node_ids_with_incoming =
              from(r in NodeRelationship,
                where: r.project_id == ^project_id and r.to_node_type == ^type,
                select: r.to_node_id
              )
              |> Repo.all()
              |> MapSet.new()

            query
            |> where([r], r.project_id == ^project_id)
            |> select([r], {r.id, r.title})
            |> Repo.all()
            |> Enum.reject(fn {id, _title} -> MapSet.member?(node_ids_with_incoming, id) end)
            |> Enum.map(fn {id, title} -> %{node_type: type, node_id: id, title: title} end)
        end
      end)

    substrate_orphans ++ legacy_orphans
  end

  defp substrate_orphans_for_type(project_id, type_key) do
    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == ^type_key
    )
    |> filter_orphans_with_inbound(project_id)
  end

  defp substrate_orphans_for_primitives(project_id, primitives) do
    from(n in GraphNode,
      where:
        n.project_id == ^project_id and n.extends_primitive in ^primitives and
          is_nil(n.archived_at)
    )
    |> filter_orphans_with_inbound(project_id)
  end

  defp filter_orphans_with_inbound(node_query, project_id) do
    with_inbound =
      from(r in NodeRelationship,
        where: r.project_id == ^project_id,
        select: r.to_node_id
      )
      |> Repo.all()
      |> MapSet.new()

    node_query
    |> select([n], {n.id, n.title, n.type_key})
    |> Repo.all()
    |> Enum.reject(fn {id, _title, _type_key} -> MapSet.member?(with_inbound, id) end)
    |> Enum.map(fn {id, title, type_key} ->
      %{node_type: type_key, node_id: id, title: title}
    end)
  end

  defp substrate_type?(type) do
    case schema_for(type) do
      GraphNode -> true
      _ -> false
    end
  end

  def density_report(project_id) do
    types = @traversable_node_types -- ["signal", "source"]

    Enum.into(types, %{}, fn type ->
      count =
        case base_query_for(type) do
          nil -> 0
          query -> query |> where([r], r.project_id == ^project_id) |> Repo.aggregate(:count)
        end

      outgoing =
        from(r in NodeRelationship,
          where: r.project_id == ^project_id and r.from_node_type == ^type
        )
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
      case base_query_for(type) do
        nil ->
          []

        query ->
          query
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
