defmodule HydraXWeb.OperatorAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias HydraX.Runtime
  alias HydraX.Runtime.Helpers

  @session_key :operator_authenticated
  @session_ts_key :operator_authenticated_at
  @session_active_key :operator_last_active_at
  @session_recent_auth_key :operator_recent_auth_at

  # Session expires after 24 hours regardless of activity
  @default_session_max_age_seconds 24 * 60 * 60
  # Session expires after 2 hours of inactivity
  @default_idle_timeout_seconds 2 * 60 * 60
  def init(action), do: action

  def session_max_age_seconds,
    do:
      Application.get_env(
        :hydra_x,
        :operator_session_max_age_seconds,
        @default_session_max_age_seconds
      )

  def idle_timeout_seconds,
    do:
      Application.get_env(
        :hydra_x,
        :operator_session_idle_timeout_seconds,
        @default_idle_timeout_seconds
      )

  def recent_auth_window_seconds do
    Runtime.effective_control_policy().recent_auth_window_minutes * 60
  end

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

  def log_in(conn, opts \\ []) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    authenticated_at = Keyword.get(opts, :authenticated_at, now)
    last_active_at = Keyword.get(opts, :last_active_at, now)
    recent_auth_at = Keyword.get(opts, :recent_auth_at, now)

    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, true)
    |> put_session(@session_ts_key, authenticated_at)
    |> put_session(@session_active_key, last_active_at)
    |> put_session(@session_recent_auth_key, recent_auth_at)
  end

  def log_out(conn) do
    conn
    |> configure_session(renew: true)
    |> delete_session(@session_key)
    |> delete_session(@session_ts_key)
    |> delete_session(@session_active_key)
    |> delete_session(@session_recent_auth_key)
  end

  def session_state(conn_or_session) do
    authenticated? = session_value(conn_or_session, @session_key) == true
    authenticated_at = session_value(conn_or_session, @session_ts_key)
    last_active_at = session_value(conn_or_session, @session_active_key)
    recent_auth_at = session_value(conn_or_session, @session_recent_auth_key)

    %{
      authenticated?: authenticated?,
      authenticated_at: authenticated_at,
      last_active_at: last_active_at,
      recent_auth_at: recent_auth_at,
      valid?: authenticated? and not session_expired?(authenticated_at, last_active_at),
      recent_auth_valid?: authenticated? and recent_auth_valid?(recent_auth_at),
      session_expires_at: expires_at(authenticated_at, session_max_age_seconds()),
      idle_expires_at: expires_at(last_active_at, idle_timeout_seconds()),
      recent_auth_expires_at: expires_at(recent_auth_at, recent_auth_window_seconds())
    }
  end

  def on_mount(:require_authenticated_operator, _params, session, socket) do
    configured? = Runtime.operator_password_configured?()
    session_state = session_state(session)
    valid? = session_state.valid?

    cond do
      not configured? ->
        {:cont,
         socket
         |> Component.assign(:operator_authenticated, false)
         |> Component.assign(:operator_session, session_state)}

      valid? ->
        {:cont,
         socket
         |> Component.assign(:operator_authenticated, true)
         |> Component.assign(:operator_session, session_state)}

      true ->
        {:halt,
         socket
         |> LiveView.put_flash(:error, "Sign in to access the Hydra-X control plane.")
         |> LiveView.redirect(to: "/login")}
    end
  end

  # -- Private helpers --

  defp session_valid?(conn) do
    session_state(conn).valid?
  end

  defp session_expired?(nil, _), do: true
  defp session_expired?(_, nil), do: true

  defp session_expired?(authenticated_at, last_active_at) do
    now = System.system_time(:second)

    now - authenticated_at > session_max_age_seconds() or
      now - last_active_at > idle_timeout_seconds()
  end

  defp recent_auth_valid?(nil), do: false

  defp recent_auth_valid?(recent_auth_at) do
    System.system_time(:second) - recent_auth_at <= recent_auth_window_seconds()
  end

  defp touch_activity(conn) do
    put_session(conn, @session_active_key, System.system_time(:second))
  end

  defp clear_expired_session(conn) do
    if get_session(conn, @session_key) == true do
      state = session_state(conn)

      Helpers.audit_auth_action("Operator session expired",
        level: "warn",
        metadata: %{
          expired_by: expired_by(state),
          authenticated_at: state.authenticated_at,
          last_active_at: state.last_active_at
        }
      )

      log_out(conn)
    else
      conn
    end
  end

  defp session_value(%Plug.Conn{} = conn, key), do: get_session(conn, key)

  defp session_value(session, key) when is_map(session),
    do: Map.get(session, Atom.to_string(key)) || Map.get(session, key)

  defp expires_at(nil, _seconds), do: nil
  defp expires_at(timestamp, seconds), do: DateTime.from_unix!(timestamp + seconds)

  defp expired_by(state) do
    now = System.system_time(:second)

    cond do
      is_integer(state.authenticated_at) and
          now - state.authenticated_at > session_max_age_seconds() ->
        "max_age"

      is_integer(state.last_active_at) and now - state.last_active_at > idle_timeout_seconds() ->
        "idle_timeout"

      true ->
        "unknown"
    end
  end
end
