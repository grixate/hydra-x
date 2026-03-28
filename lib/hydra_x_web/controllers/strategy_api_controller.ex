defmodule HydraXWeb.StrategyAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Strategy
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    strategies =
      Product.list_strategies(project_id,
        status: conn.params["status"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.strategy_json/1)

    json(conn, %{data: strategies})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    strategy = project_id |> Product.get_project_strategy!(id) |> ProductPayload.strategy_json()
    json(conn, %{data: strategy})
  end

  def create(conn, %{"project_id" => project_id, "strategy" => params}) do
    with {:ok, %Strategy{} = strategy} <- Product.create_strategy(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.strategy_json(strategy)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "strategy" => params}) do
    strategy = Product.get_project_strategy!(project_id, id)
    with {:ok, %Strategy{} = updated} <- Product.update_strategy(strategy, params) do
      json(conn, %{data: ProductPayload.strategy_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    strategy = Product.get_project_strategy!(project_id, id)
    with {:ok, %Strategy{}} <- Product.delete_strategy(strategy) do
      send_resp(conn, :no_content, "")
    end
  end
end
