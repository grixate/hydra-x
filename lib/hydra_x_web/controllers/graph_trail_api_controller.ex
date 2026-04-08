defmodule HydraXWeb.GraphTrailAPIController do
  use HydraXWeb, :controller

  import Ecto.Query

  alias HydraX.Product.Graph
  alias HydraX.Product.GraphEdge
  alias HydraX.Repo

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id} = params) do
    node_type = params["node_type"] || "insight"
    node_id = parse_int(params["node_id"])
    direction = params["direction"] || "both"
    depth = parse_int(params["depth"]) || 5

    project_id = parse_int(project_id)

    center = build_center(project_id, node_type, node_id)

    upstream =
      if direction in ["both", "upstream"],
        do: resolve_chain(project_id, Graph.trace_upstream(project_id, node_type, node_id, max_depth: depth)),
        else: []

    downstream =
      if direction in ["both", "downstream"],
        do: resolve_chain(project_id, Graph.trace_downstream(project_id, node_type, node_id, max_depth: depth)),
        else: []

    flags = Graph.open_flags(project_id, node_type: node_type)
    node_flags = Enum.filter(flags, fn f -> f.node_id == node_id end)

    json(conn, %{
      data: %{
        center: center,
        upstream: upstream,
        downstream: downstream,
        flags:
          Enum.map(node_flags, fn f ->
            %{
              id: f.id,
              flag_type: f.flag_type,
              reason: f.reason,
              status: f.status,
              source_agent: f.source_agent
            }
          end)
      }
    })
  end

  defp build_center(project_id, node_type, node_id) do
    base =
      case Graph.resolve_node(node_type, node_id) do
        {:ok, record} when not is_nil(record) ->
          result = %{
            node_type: node_type,
            node_id: node_id,
            title: Map.get(record, :title, ""),
            body: resolve_body(record),
            status: Map.get(record, :status, "") || "",
            inserted_at: Map.get(record, :inserted_at),
            updated_at: Map.get(record, :updated_at),
            metadata: Map.get(record, :metadata, %{}) || %{}
          }

          # Add decision-specific fields
          result =
            if node_type == "decision" do
              result
              |> Map.put(:alternatives_considered, Map.get(record, :alternatives_considered))
              |> Map.put(:decided_by, Map.get(record, :decided_by))
              |> Map.put(:decided_at, Map.get(record, :decided_at))
            else
              result
            end

          result

        _ ->
          %{node_type: node_type, node_id: node_id, title: "not found", status: "unknown",
            body: "", inserted_at: nil, updated_at: nil, metadata: %{},
            upstream_counts: %{}, downstream_counts: %{}, constraints: []}
      end

    # Add connection counts
    upstream_counts = edge_counts_by_type(project_id, node_type, node_id, :upstream)
    downstream_counts = edge_counts_by_type(project_id, node_type, node_id, :downstream)

    # Add constraints
    constraints = linked_constraints(project_id, node_type, node_id)

    base
    |> Map.put(:upstream_counts, upstream_counts)
    |> Map.put(:downstream_counts, downstream_counts)
    |> Map.put(:constraints, constraints)
  end

  defp edge_counts_by_type(project_id, node_type, node_id, :upstream) do
    GraphEdge
    |> where([e],
      e.project_id == ^project_id and
        e.to_node_type == ^to_string(node_type) and
        e.to_node_id == ^node_id
    )
    |> group_by([e], e.from_node_type)
    |> select([e], {e.from_node_type, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp edge_counts_by_type(project_id, node_type, node_id, :downstream) do
    GraphEdge
    |> where([e],
      e.project_id == ^project_id and
        e.from_node_type == ^to_string(node_type) and
        e.from_node_id == ^node_id
    )
    |> group_by([e], e.to_node_type)
    |> select([e], {e.to_node_type, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp linked_constraints(project_id, node_type, node_id) do
    constraint_edges =
      GraphEdge
      |> where([e],
        e.project_id == ^project_id and
          e.to_node_type == ^to_string(node_type) and
          e.to_node_id == ^node_id and
          e.kind == "constrains"
      )
      |> Repo.all()

    refs = Enum.map(constraint_edges, fn e -> {e.from_node_type, e.from_node_id} end)

    if refs == [] do
      []
    else
      Graph.resolve_nodes(refs)
      |> Enum.map(fn {_type, _id, record} ->
        %{
          id: record.id,
          title: Map.get(record, :title, ""),
          body: String.slice(Map.get(record, :body, "") || "", 0, 200)
        }
      end)
    end
  end

  defp resolve_chain(project_id, nodes) do
    refs = Enum.map(nodes, fn n -> {n.node_type, n.node_id} end)
    resolved = Graph.resolve_nodes(refs) |> Map.new(fn {type, id, record} -> {{type, id}, record} end)

    # Batch count edges for all chain nodes in 2 queries instead of 2*N
    upstream_counts = batch_edge_counts(project_id, refs, :upstream)
    downstream_counts = batch_edge_counts(project_id, refs, :downstream)

    Enum.map(nodes, fn n ->
      record = Map.get(resolved, {n.node_type, n.node_id})
      key = {to_string(n.node_type), n.node_id}

      %{
        node_type: n.node_type,
        node_id: n.node_id,
        edge_kind: n.edge_kind,
        title: if(record, do: Map.get(record, :title, ""), else: ""),
        status: if(record, do: Map.get(record, :status, ""), else: ""),
        summary: if(record, do: String.slice(resolve_body(record), 0, 200), else: ""),
        updated_at: if(record, do: Map.get(record, :updated_at), else: nil),
        upstream_count: Map.get(upstream_counts, key, 0),
        downstream_count: Map.get(downstream_counts, key, 0)
      }
    end)
  end

  defp batch_edge_counts(_project_id, [], _direction), do: %{}

  defp batch_edge_counts(project_id, refs, direction) do
    # Build concat keys for matching: "type:id"
    keys = Enum.map(refs, fn {t, id} -> "#{t}:#{id}" end) |> Enum.uniq()

    query =
      case direction do
        :upstream ->
          GraphEdge
          |> where([e], e.project_id == ^project_id)
          |> where([e], fragment("? || ':' || ?", e.to_node_type, e.to_node_id) in ^keys)
          |> group_by([e], [e.to_node_type, e.to_node_id])
          |> select([e], {e.to_node_type, e.to_node_id, count(e.id)})

        :downstream ->
          GraphEdge
          |> where([e], e.project_id == ^project_id)
          |> where([e], fragment("? || ':' || ?", e.from_node_type, e.from_node_id) in ^keys)
          |> group_by([e], [e.from_node_type, e.from_node_id])
          |> select([e], {e.from_node_type, e.from_node_id, count(e.id)})
      end

    query
    |> Repo.all()
    |> Map.new(fn {t, id, cnt} -> {{t, id}, cnt} end)
  end

  # Schemas use different field names for the main text content
  defp resolve_body(record) do
    (Map.get(record, :body) || Map.get(record, :content) || Map.get(record, :description) || "")
  end

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
