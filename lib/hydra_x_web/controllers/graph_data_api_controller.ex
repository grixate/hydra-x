defmodule HydraXWeb.GraphDataAPIController do
  use HydraXWeb, :controller

  import Ecto.Query
  alias HydraX.Product
  alias HydraX.Product.Graph

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id}) do
    project_id = parse_int(project_id)

    nodes =
      Enum.flat_map(Graph.node_types(), fn type ->
        case Graph.schema_for(type) do
          nil ->
            []

          schema ->
            try do
              schema
              |> where([r], r.project_id == ^project_id)
              |> HydraX.Repo.all()
              |> Enum.map(fn record ->
                %{
                  id: "#{type}-#{record.id}",
                  node_type: type,
                  node_id: record.id,
                  title: Map.get(record, :title, ""),
                  status: Map.get(record, :status, "") || "active",
                  body: String.slice(Map.get(record, :body, "") || "", 0, 200),
                  inserted_at: Map.get(record, :inserted_at),
                  updated_at: Map.get(record, :updated_at)
                }
              end)
            rescue
              _ -> []
            end
        end
      end)

    edges = Product.list_graph_edges(project_id)

    edges_json =
      Enum.map(edges, fn e ->
        %{
          id: e.id,
          source: "#{e.from_node_type}-#{e.from_node_id}",
          target: "#{e.to_node_type}-#{e.to_node_id}",
          kind: e.kind,
          weight: e.weight
        }
      end)

    flags =
      Graph.open_flags(project_id)
      |> Enum.map(fn flag ->
        %{
          id: flag.id,
          node_id: "#{flag.node_type}-#{flag.node_id}",
          flag_type: flag.flag_type,
          reason: flag.reason,
          status: flag.status,
          source_agent: flag.source_agent
        }
      end)

    # Count upstream (incoming) and downstream (outgoing) connections per node
    {upstream_counts, downstream_counts} =
      Enum.reduce(edges_json, {%{}, %{}}, fn e, {up, down} ->
        {
          Map.update(up, e.target, 1, &(&1 + 1)),
          Map.update(down, e.source, 1, &(&1 + 1))
        }
      end)

    # Count open flags per node
    flag_counts =
      Enum.reduce(flags, %{}, fn f, acc ->
        Map.update(acc, f.node_id, 1, &(&1 + 1))
      end)

    nodes =
      Enum.map(nodes, fn node ->
        node
        |> Map.put(:upstream_count, Map.get(upstream_counts, node.id, 0))
        |> Map.put(:downstream_count, Map.get(downstream_counts, node.id, 0))
        |> Map.put(:connection_count, Map.get(upstream_counts, node.id, 0) + Map.get(downstream_counts, node.id, 0))
        |> Map.put(:flag_count, Map.get(flag_counts, node.id, 0))
      end)

    density = Graph.density_report(project_id)

    json(conn, %{data: %{nodes: nodes, edges: edges_json, flags: flags, density: density}})
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value), do: String.to_integer(value)
end
