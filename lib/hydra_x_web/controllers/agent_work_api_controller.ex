defmodule HydraXWeb.AgentWorkAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.MyWork

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id, "agent_slug" => agent_slug}) do
    data = MyWork.agent_work(project_id, agent_slug)
    json(conn, %{data: data})
  end
end
