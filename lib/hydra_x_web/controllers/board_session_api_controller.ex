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

  def events(conn, %{"project_id" => _project_id, "session_id" => session_id}) do
    events =
      Product.list_board_session_events(session_id)
      |> Enum.map(fn e ->
        %{
          id: e.id,
          event_type: e.event_type,
          actor_type: e.actor_type,
          actor_name: e.actor_name,
          target_type: e.target_type,
          target_id: e.target_id,
          target_title: e.target_title,
          metadata: e.metadata || %{},
          inserted_at: e.inserted_at
        }
      end)

    json(conn, %{data: events})
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    session = Product.get_project_board_session!(project_id, id)

    with {:ok, %BoardSession{}} <- Product.delete_board_session(session) do
      send_resp(conn, :no_content, "")
    end
  end
end
