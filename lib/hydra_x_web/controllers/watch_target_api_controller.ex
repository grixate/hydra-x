defmodule HydraXWeb.WatchTargetAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.ContinuousResearch
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    targets = ContinuousResearch.list_watch_targets(project_id)
    json(conn, %{data: Enum.map(targets, &ProductPayload.watch_target_json/1)})
  end

  def create(conn, %{"project_id" => project_id, "watch_target" => params}) do
    with {:ok, target} <- ContinuousResearch.add_watch_target(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.watch_target_json(target)})
    end
  end

  def delete(conn, %{"project_id" => _project_id, "id" => id}) do
    with {:ok, _target} <- ContinuousResearch.remove_watch_target(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
