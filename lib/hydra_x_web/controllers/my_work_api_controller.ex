defmodule HydraXWeb.MyWorkAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.MyWork

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    data = MyWork.generate(project_id)
    json(conn, %{data: data})
  end
end
