defmodule HydraXWeb.GraphNodesAPIController do
  use HydraXWeb, :controller

  import Ecto.Query
  alias HydraX.Product
  alias HydraX.Product.Graph

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    project_id = parse_int(project_id)

    # Collect all nodes across all types
    nodes =
      Enum.flat_map(Graph.node_types(), fn type ->
        case Graph.schema_for(type) do
          nil ->
            []

          schema ->
            try do
              schema
              |> Ecto.Query.where([r], r.project_id == ^project_id)
              |> HydraX.Repo.all()
              |> Enum.map(fn record ->
                %{
                  id: "#{type}-#{record.id}",
                  db_id: record.id,
                  node_type: type,
                  title: Map.get(record, :title, ""),
                  status: Map.get(record, :status, ""),
                  body_excerpt: String.slice(Map.get(record, :body, "") || "", 0, 200),
                  updated_at: Map.get(record, :updated_at)
                }
              end)
            rescue
              _ -> []
            end
        end
      end)

    # Collect all edges
    edges = Product.list_graph_edges(project_id)

    edges_json =
      Enum.map(edges, fn e ->
        %{
          id: "edge-#{e.id}",
          source: "#{e.from_node_type}-#{e.from_node_id}",
          target: "#{e.to_node_type}-#{e.to_node_id}",
          kind: e.kind,
          weight: e.weight
        }
      end)

    json(conn, %{data: %{nodes: nodes, edges: edges_json}})
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value), do: String.to_integer(value)
end
