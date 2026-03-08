defmodule HydraXWeb.OperatorAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias HydraX.Runtime

  @session_key :operator_authenticated
  @session_ts_key :operator_authenticated_at
  @session_active_key :operator_last_active_at

  # Session expires after 24 hours regardless of activity
  @session_max_age_seconds 24 * 60 * 60
  # Session expires after 2 hours of inactivity
  @idle_timeout_seconds 2 * 60 * 60

  def init(action), do: action

  def call(conn, :redirect_if_authenticated) do
    if Runtime.operator_password_configured?() and session_valid?(conn) do
      conn
      |> touch_activity()
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end

  def call(conn, :require_authenticated_operator) do
    if Runtime.operator_password_configured?() and not session_valid?(conn) do
      conn
      |> clear_expired_session()
      |> put_flash(:error, "Sign in to access the Hydra-X control plane.")
      |> redirect(to: "/login")
      |> halt()
    else
      conn
      |> touch_activity()
    end
  end

  def log_in(conn) do
    now = System.system_time(:second)

    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, true)
    |> put_session(@session_ts_key, now)
    |> put_session(@session_active_key, now)
  end

  def log_out(conn) do
    conn
    |> configure_session(renew: true)
    |> delete_session(@session_key)
    |> delete_session(@session_ts_key)
    |> delete_session(@session_active_key)
  end

  def on_mount(:require_authenticated_operator, _params, session, socket) do
    configured? = Runtime.operator_password_configured?()
    valid? = session_valid_from_map?(session)

    cond do
      not configured? ->
        {:cont, Component.assign(socket, :operator_authenticated, false)}

      valid? ->
        {:cont, Component.assign(socket, :operator_authenticated, true)}

      true ->
        {:halt,
         socket
         |> LiveView.put_flash(:error, "Sign in to access the Hydra-X control plane.")
         |> LiveView.redirect(to: "/login")}
    end
  end

  # -- Private helpers --

  defp session_valid?(conn) do
    get_session(conn, @session_key) == true and
      not session_expired?(
        get_session(conn, @session_ts_key),
        get_session(conn, @session_active_key)
      )
  end

  defp session_valid_from_map?(session) do
    Map.get(session, Atom.to_string(@session_key)) == true and
      not session_expired?(
        Map.get(session, Atom.to_string(@session_ts_key)),
        Map.get(session, Atom.to_string(@session_active_key))
      )
  end

  defp session_expired?(nil, _), do: true
  defp session_expired?(_, nil), do: true

  defp session_expired?(authenticated_at, last_active_at) do
    now = System.system_time(:second)
    now - authenticated_at > @session_max_age_seconds or now - last_active_at > @idle_timeout_seconds
  end

  defp touch_activity(conn) do
    put_session(conn, @session_active_key, System.system_time(:second))
  end

  defp clear_expired_session(conn) do
    if get_session(conn, @session_key) == true do
      log_out(conn)
    else
      conn
    end
  end
end
