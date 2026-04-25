defmodule HydraXWeb.OperatorAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias HydraX.Accounts
  alias HydraX.Runtime.Helpers
  alias HydraXWeb.Plugs.UserAuth

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
    Application.get_env(:hydra_x, :operator_recent_auth_window_seconds, 15 * 60)
  end

  def call(conn, :redirect_if_authenticated) do
    if session_valid?(conn) do
      conn
      |> touch_activity()
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end

  def call(conn, :require_authenticated_operator) do
    if not session_valid?(conn) do
      state = session_state(conn)

      redirect_target =
        if get_session(conn, UserAuth.session_key()) do
          "/login?expired=#{expired_by(state)}"
        else
          unauthenticated_destination()
        end

      conn
      |> clear_expired_session(state)
      |> put_flash(:error, "Sign in to access the Hydra-X control plane.")
      |> redirect(to: redirect_target)
      |> halt()
    else
      conn
      |> touch_activity()
    end
  end

  def log_in(conn, %HydraX.Accounts.User{} = user, opts) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    authenticated_at = Keyword.get(opts, :authenticated_at, now)
    last_active_at = Keyword.get(opts, :last_active_at, now)
    recent_auth_at = Keyword.get(opts, :recent_auth_at, now)

    conn
    |> UserAuth.put_user_session(user)
    |> configure_session(renew: true)
    |> put_session(@session_ts_key, authenticated_at)
    |> put_session(@session_active_key, last_active_at)
      |> put_session(@session_recent_auth_key, recent_auth_at)
  end

  def log_in(conn, %HydraX.Accounts.User{} = user) do
    log_in(conn, user, [])
  end

  def log_in(conn, opts) when is_list(opts) do
    user = Keyword.get(opts, :user) || ensure_test_operator_user!()
    log_in(conn, user, opts)
  end

  def log_in(conn), do: log_in(conn, [])

  def log_out(conn) do
    conn
    |> UserAuth.clear_user_session()
    |> configure_session(renew: true)
    |> delete_session(@session_ts_key)
    |> delete_session(@session_active_key)
    |> delete_session(@session_recent_auth_key)
  end

  def session_state(conn_or_session) do
    user_id = session_value(conn_or_session, UserAuth.session_key())
    user = if is_binary(user_id), do: Accounts.get_user(user_id)
    authenticated? = not is_nil(user)
    operator? = Accounts.operator?(user)
    authenticated_at = session_value(conn_or_session, @session_ts_key)
    last_active_at = session_value(conn_or_session, @session_active_key)
    recent_auth_at = session_value(conn_or_session, @session_recent_auth_key)

    %{
      authenticated?: authenticated?,
      operator?: operator?,
      user: user,
      user_id: user_id,
      authenticated_at: authenticated_at,
      last_active_at: last_active_at,
      recent_auth_at: recent_auth_at,
      valid?: authenticated? and operator? and not session_expired?(authenticated_at, last_active_at),
      recent_auth_valid?: authenticated? and recent_auth_valid?(recent_auth_at),
      session_expires_at: expires_at(authenticated_at, session_max_age_seconds()),
      idle_expires_at: expires_at(last_active_at, idle_timeout_seconds()),
      recent_auth_expires_at: expires_at(recent_auth_at, recent_auth_window_seconds())
    }
  end

  def on_mount(:require_authenticated_operator, _params, session, socket) do
    session_state = session_state(session)
    valid? = session_state.valid?

    cond do
      valid? ->
        {:cont,
         socket
         |> Component.assign(:operator_authenticated, true)
         |> Component.assign(:current_user, session_state.user)
         |> Component.assign(:operator_session, session_state)}

      true ->
        {:halt,
         socket
         |> LiveView.put_flash(:error, "Sign in to access the Hydra-X control plane.")
         |> LiveView.redirect(to: unauthenticated_destination())}
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

  defp clear_expired_session(conn, state) do
    if get_session(conn, UserAuth.session_key()) do
      state = state || session_state(conn)

      Helpers.audit_auth_action("Operator session expired",
        level: "warn",
        metadata: %{
          expired_by: expired_by(state),
          authenticated_at: state.authenticated_at,
          last_active_at: state.last_active_at,
          session_expires_at: state.session_expires_at,
          idle_expires_at: state.idle_expires_at
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

  defp unauthenticated_destination do
    if Accounts.operator_user_exists?(), do: "/login", else: "/register"
  end

  defp ensure_test_operator_user! do
    if Application.get_env(:hydra_x, :env) != :test do
      raise ArgumentError, "OperatorAuth.log_in/2 requires a user outside test"
    end

    case HydraX.Accounts.get_user_by_email("operator@test.example.com") do
      %HydraX.Accounts.User{} = user ->
        if Accounts.operator?(user) do
          user
        else
          user
          |> HydraX.Accounts.User.operator_changeset()
          |> HydraX.Repo.update!()
        end

      nil ->
        {:ok, %{user: user}} =
          Accounts.register_first_operator(%{
            "email" => "operator@test.example.com",
            "display_name" => "Test Operator",
            "password" => "hydra-password-123",
            "password_confirmation" => "hydra-password-123"
          })

        user
    end
  end

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
