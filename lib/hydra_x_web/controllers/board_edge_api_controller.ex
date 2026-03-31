defmodule HydraXWeb.BoardEdgeAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.BoardEdge
  alias HydraX.Repo
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def create(conn, %{"session_id" => session_id, "board_edge" => params}) do
    with {:ok, %BoardEdge{} = edge} <- Product.create_board_edge(session_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.board_edge_json(edge)})
    end
  end

  def delete(conn, %{"id" => id}) do
    edge = Repo.get!(BoardEdge, id)

    with {:ok, %BoardEdge{}} <- Product.delete_board_edge(edge) do
      send_resp(conn, :no_content, "")
    end
  end
end
