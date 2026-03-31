defmodule HydraXWeb.GraphEdgeAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def create(conn, %{"project_id" => project_id} = params) do
    project_id = parse_int(project_id)

    attrs = %{
      "project_id" => project_id,
      "from_node_type" => params["from_node_type"],
      "from_node_id" => parse_int(params["from_node_id"]),
      "to_node_type" => params["to_node_type"],
      "to_node_id" => parse_int(params["to_node_id"]),
      "kind" => params["kind"],
      "weight" => params["weight"] || 1.0,
      "metadata" => params["metadata"] || %{}
    }

    case Product.create_graph_edge(attrs) do
      {:ok, edge} ->
        conn
        |> put_status(:created)
        |> json(%{data: serialize_edge(edge)})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def show(conn, %{"id" => id}) do
    edge = Product.get_graph_edge!(parse_int(id))
    json(conn, %{data: serialize_edge(edge)})
  end

  def delete(conn, %{"id" => id}) do
    edge = Product.get_graph_edge!(parse_int(id))

    case Product.delete_graph_edge(edge) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp serialize_edge(edge) do
    %{
      id: edge.id,
      source: "#{edge.from_node_type}-#{edge.from_node_id}",
      target: "#{edge.to_node_type}-#{edge.to_node_id}",
      from_node_type: edge.from_node_type,
      from_node_id: edge.from_node_id,
      to_node_type: edge.to_node_type,
      to_node_id: edge.to_node_id,
      kind: edge.kind,
      weight: edge.weight,
      metadata: edge.metadata,
      inserted_at: edge.inserted_at,
      updated_at: edge.updated_at
    }
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value), do: String.to_integer(value)
end
