defmodule HydraXWeb.ArchitectureNodeAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.ArchitectureNode
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    nodes =
      Product.list_architecture_nodes(project_id,
        status: conn.params["status"],
        node_type: conn.params["node_type"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.architecture_node_json/1)

    json(conn, %{data: nodes})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    node = project_id |> Product.get_project_architecture_node!(id) |> ProductPayload.architecture_node_json()
    json(conn, %{data: node})
  end

  def create(conn, %{"project_id" => project_id, "architecture_node" => params}) do
    with {:ok, %ArchitectureNode{} = node} <- Product.create_architecture_node(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.architecture_node_json(node)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "architecture_node" => params}) do
    node = Product.get_project_architecture_node!(project_id, id)
    with {:ok, %ArchitectureNode{} = updated} <- Product.update_architecture_node(node, params) do
      json(conn, %{data: ProductPayload.architecture_node_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    node = Product.get_project_architecture_node!(project_id, id)
    with {:ok, %ArchitectureNode{}} <- Product.delete_architecture_node(node) do
      send_resp(conn, :no_content, "")
    end
  end
end
