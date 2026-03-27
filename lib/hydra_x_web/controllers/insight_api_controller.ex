defmodule HydraXWeb.InsightAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Insight
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    insights =
      Product.list_insights(project_id,
        status: conn.params["status"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.insight_json/1)

    json(conn, %{data: insights})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    insight =
      project_id
      |> Product.get_project_insight!(id)
      |> ProductPayload.insight_json()

    json(conn, %{data: insight})
  end

  def create(conn, %{"project_id" => project_id, "insight" => params}) do
    with {:ok, %Insight{} = insight} <- Product.create_insight(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.insight_json(insight)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "insight" => params}) do
    insight = Product.get_project_insight!(project_id, id)

    with {:ok, %Insight{} = updated} <- Product.update_insight(insight, params) do
      json(conn, %{data: ProductPayload.insight_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    insight = Product.get_project_insight!(project_id, id)

    with {:ok, %Insight{}} <- Product.delete_insight(insight) do
      send_resp(conn, :no_content, "")
    end
  end
end
