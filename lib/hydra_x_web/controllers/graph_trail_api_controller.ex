defmodule HydraXWeb.GraphTrailAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.Graph

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id} = params) do
    node_type = params["node_type"] || "insight"
    node_id = parse_int(params["node_id"])
    direction = params["direction"] || "both"
    depth = parse_int(params["depth"]) || 5

    project_id = parse_int(project_id)

    center =
      case Graph.resolve_node(node_type, node_id) do
        {:ok, record} when not is_nil(record) ->
          %{
            node_type: node_type,
            node_id: node_id,
            title: Map.get(record, :title, ""),
            body: String.slice(Map.get(record, :body, ""), 0, 500),
            status: Map.get(record, :status, ""),
            updated_at: Map.get(record, :updated_at)
          }

        _ ->
          %{node_type: node_type, node_id: node_id, title: "not found", status: "unknown"}
      end

    upstream =
      if direction in ["both", "upstream"],
        do: resolve_chain(Graph.trace_upstream(project_id, node_type, node_id, max_depth: depth)),
        else: []

    downstream =
      if direction in ["both", "downstream"],
        do: resolve_chain(Graph.trace_downstream(project_id, node_type, node_id, max_depth: depth)),
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

  defp resolve_chain(nodes) do
    refs = Enum.map(nodes, fn n -> {n.node_type, n.node_id} end)
    resolved = Graph.resolve_nodes(refs) |> Map.new(fn {type, id, record} -> {{type, id}, record} end)

    Enum.map(nodes, fn n ->
      record = Map.get(resolved, {n.node_type, n.node_id})

      %{
        node_type: n.node_type,
        node_id: n.node_id,
        edge_kind: n.edge_kind,
        title: if(record, do: Map.get(record, :title, ""), else: ""),
        status: if(record, do: Map.get(record, :status, ""), else: ""),
        summary: if(record, do: String.slice(Map.get(record, :body, ""), 0, 200), else: "")
      }
    end)
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
