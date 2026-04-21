defmodule HydraXWeb.Plugs.UserAuth do
  @moduledoc """
  Lightweight user-session pipeline for `/api/v1/*` and upcoming
  user-scoped routes.

  Cycle 2 simple-auth: no OAuth, no email. A signed-in user is
  identified by a `:user_id` in the Phoenix session cookie; the plug
  loads the full `User` and assigns it to `conn.assigns[:current_user]`.

  Call `put_user_session/2` from controllers after any sign-in path
  (dev-login, future magic-link, future OAuth) to mint the session.
  """

  import Plug.Conn

  @session_key :hydra_user_id

  alias HydraX.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_session(conn)

    case get_session(conn, @session_key) do
      nil ->
        assign(conn, :current_user, nil)

      id when is_binary(id) ->
        case Accounts.get_user(id) do
          nil ->
            conn
            |> delete_session(@session_key)
            |> assign(:current_user, nil)

          user ->
            assign(conn, :current_user, user)
        end
    end
  end

  @doc "Mint a session for `user` on the connection."
  def put_user_session(conn, %HydraX.Accounts.User{id: id}) do
    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, id)
  end

  @doc "Tear down the user session."
  def clear_user_session(conn) do
    conn
    |> configure_session(drop: true)
  end

  @doc """
  Gate a route behind a live user. Sends 401 if no user is loaded.

  Used as a pipeline plug on `:authenticated_user`.
  """
  def require_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %HydraX.Accounts.User{} ->
        conn

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "authentication_required"}))
        |> halt()
    end
  end
end
