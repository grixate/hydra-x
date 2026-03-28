defmodule HydraXWeb.DesignNodeAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.DesignNode
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    nodes =
      Product.list_design_nodes(project_id,
        status: conn.params["status"],
        node_type: conn.params["node_type"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.design_node_json/1)

    json(conn, %{data: nodes})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    node = project_id |> Product.get_project_design_node!(id) |> ProductPayload.design_node_json()
    json(conn, %{data: node})
  end

  def create(conn, %{"project_id" => project_id, "design_node" => params}) do
    with {:ok, %DesignNode{} = node} <- Product.create_design_node(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.design_node_json(node)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "design_node" => params}) do
    node = Product.get_project_design_node!(project_id, id)
    with {:ok, %DesignNode{} = updated} <- Product.update_design_node(node, params) do
      json(conn, %{data: ProductPayload.design_node_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    node = Product.get_project_design_node!(project_id, id)
    with {:ok, %DesignNode{}} <- Product.delete_design_node(node) do
      send_resp(conn, :no_content, "")
    end
  end
end
