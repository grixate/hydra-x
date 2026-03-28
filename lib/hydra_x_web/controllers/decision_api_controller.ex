defmodule HydraXWeb.DecisionAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Decision
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    decisions =
      Product.list_decisions(project_id,
        status: conn.params["status"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.decision_json/1)

    json(conn, %{data: decisions})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    decision = project_id |> Product.get_project_decision!(id) |> ProductPayload.decision_json()
    json(conn, %{data: decision})
  end

  def create(conn, %{"project_id" => project_id, "decision" => params}) do
    with {:ok, %Decision{} = decision} <- Product.create_decision(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.decision_json(decision)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "decision" => params}) do
    decision = Product.get_project_decision!(project_id, id)
    with {:ok, %Decision{} = updated} <- Product.update_decision(decision, params) do
      json(conn, %{data: ProductPayload.decision_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    decision = Product.get_project_decision!(project_id, id)
    with {:ok, %Decision{}} <- Product.delete_decision(decision) do
      send_resp(conn, :no_content, "")
    end
  end
end
