defmodule HydraXWeb.BoardSessionAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.BoardSession
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    sessions =
      Product.list_board_sessions(project_id,
        status: conn.params["status"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.board_session_json/1)

    json(conn, %{data: sessions})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    session =
      project_id
      |> Product.get_project_board_session!(id)
      |> ProductPayload.board_session_json()

    json(conn, %{data: session})
  end

  def create(conn, %{"project_id" => project_id, "board_session" => params}) do
    with {:ok, %BoardSession{} = session} <- Product.create_board_session(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.board_session_json(session)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "board_session" => params}) do
    session = Product.get_project_board_session!(project_id, id)

    with {:ok, %BoardSession{} = updated} <- Product.update_board_session(session, params) do
      json(conn, %{data: ProductPayload.board_session_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    session = Product.get_project_board_session!(project_id, id)

    with {:ok, %BoardSession{}} <- Product.delete_board_session(session) do
      send_resp(conn, :no_content, "")
    end
  end
end
