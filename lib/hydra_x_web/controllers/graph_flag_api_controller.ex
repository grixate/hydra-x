defmodule HydraXWeb.GraphFlagAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Graph
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    flags =
      Product.list_graph_flags(project_id,
        status: conn.params["status"],
        flag_type: conn.params["flag_type"],
        node_type: conn.params["node_type"]
      )
      |> Enum.map(&ProductPayload.graph_flag_json/1)

    json(conn, %{data: flags})
  end

  def resolve(conn, %{"project_id" => _project_id, "id" => id}) do
    resolved_by = conn.params["resolved_by"] || "operator"

    with {:ok, flag} <- Graph.resolve_flag(id, resolved_by) do
      json(conn, %{data: ProductPayload.graph_flag_json(flag)})
    end
  end
end
