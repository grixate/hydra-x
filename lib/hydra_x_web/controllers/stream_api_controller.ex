defmodule HydraXWeb.StreamAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.Stream

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    opts = [role: params["role"] || "founder"]

    stream = Stream.generate_stream(project_id, opts)

    json(conn, %{
      data: %{
        right_now: stream.right_now,
        recently: stream.recently,
        emerging: stream.emerging
      }
    })
  end
end
