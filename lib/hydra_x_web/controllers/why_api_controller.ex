defmodule HydraXWeb.WhyAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.WhyProse

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id} = params) do
    node_type = params["node_type"]
    node_id = params["node_id"]
    force = params["force"] == "true"

    case WhyProse.build(project_id, node_type, node_id, force_regenerate: force) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
