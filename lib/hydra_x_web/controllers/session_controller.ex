defmodule HydraXWeb.SessionController do
  use HydraXWeb, :controller

  alias HydraX.Runtime
  alias HydraX.Runtime.Helpers
  alias HydraX.Runtime.OperatorSecret
  alias HydraX.Security.LoginThrottle
  alias HydraXWeb.OperatorAuth

  def new(conn, params) do
    render_login(conn,
      reauth?: params["reauth"] == "1",
      changeset: OperatorSecret.changeset(%OperatorSecret{}, %{})
    )
  end

  def create(conn, %{"operator_secret" => params}) do
    ip = client_ip(conn)
    throttle = LoginThrottle.state(ip)

    if throttle.rate_limited? do
      Helpers.audit_auth_action("Blocked operator login due to rate limit",
        level: "warn",
        metadata: %{
          ip: ip,
          window_seconds: throttle.window_seconds,
          max_attempts: throttle.max_attempts,
          retry_after_seconds: throttle.retry_after_seconds
        }
      )

      render_login(conn,
        reauth?: false,
        throttle: throttle,
        changeset:
          OperatorSecret.changeset(%OperatorSecret{}, %{})
          |> Ecto.Changeset.add_error(:password, "too many attempts, try again later")
      )
    else
      case Runtime.authenticate_operator(params["password"] || "") do
        :ok ->
          LoginThrottle.clear_attempts(ip)

          Helpers.audit_auth_action("Operator login succeeded",
            metadata: %{ip: ip}
          )

          conn
          |> OperatorAuth.log_in()
          |> put_flash(:info, "Signed in.")
          |> redirect(to: "/")

        {:error, :not_configured} ->
          conn
          |> put_flash(:info, "No operator password is configured yet. Set one on /setup.")
          |> redirect(to: "/setup")

        {:error, :unauthorized} ->
          LoginThrottle.record_attempt(ip)
          attempts = LoginThrottle.current_attempts(ip)

          Helpers.audit_auth_action("Operator login failed",
            level: "warn",
            metadata: %{
              ip: ip,
              attempts: attempts,
              window_seconds: LoginThrottle.window_seconds()
            }
          )

          render_login(conn,
            reauth?: false,
            throttle: LoginThrottle.state(ip),
            changeset:
              OperatorSecret.changeset(%OperatorSecret{}, %{})
              |> Ecto.Changeset.add_error(:password, "is invalid")
          )
      end
    end
  end

  def delete(conn, _params) do
    Helpers.audit_auth_action("Operator logged out",
      metadata: %{ip: client_ip(conn)}
    )

    conn
    |> OperatorAuth.log_out()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: "/login")
  end

  defp render_login(conn, opts) do
    throttle = Keyword.get(opts, :throttle, LoginThrottle.state(client_ip(conn)))

    render(conn, :new,
      password_configured?: Runtime.operator_password_configured?(),
      reauth?: Keyword.get(opts, :reauth?, false),
      changeset: Keyword.fetch!(opts, :changeset),
      throttle: throttle,
      session_max_age_seconds: OperatorAuth.session_max_age_seconds(),
      idle_timeout_seconds: OperatorAuth.idle_timeout_seconds(),
      recent_auth_window_seconds: OperatorAuth.recent_auth_window_seconds()
    )
  end

  defp client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
