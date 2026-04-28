defmodule HydraXWeb.SessionController do
  use HydraXWeb, :controller

  alias HydraX.Accounts
  alias HydraX.Security.LoginThrottle
  alias HydraX.Runtime.Helpers
  alias HydraXWeb.OperatorAuth

  def new(conn, params) do
    if OperatorAuth.session_state(conn).valid? do
      redirect(conn, to: ~p"/")
    else
      render_login(conn,
        expired_reason: Helpers.blank_to_nil(params["expired"]),
        form: to_form(%{}, as: :user)
      )
    end
  end

  def create(conn, %{"user" => params}) do
    ip = client_ip(conn)
    throttle = LoginThrottle.state(ip)

    cond do
      throttle.rate_limited? ->
        Helpers.audit_auth_action("Blocked operator login due to rate limit",
          level: "warn",
          metadata: %{
            ip: ip,
            window_seconds: throttle.window_seconds,
            max_attempts: throttle.max_attempts
          }
        )

        render_login(conn,
          throttle: throttle,
          form: to_form(params, as: :user),
          error: "Too many attempts, try again later."
        )

      true ->
        case Accounts.authenticate_user(params["email"] || "", params["password"] || "") do
          {:ok, user} ->
            if Accounts.operator?(user) do
              LoginThrottle.clear_attempts(ip)

              Helpers.audit_auth_action("Operator login succeeded",
                metadata: %{ip: ip, user_id: user.id}
              )

              conn
              |> OperatorAuth.log_in(user)
              |> put_flash(:info, "Signed in.")
              |> redirect(to: ~p"/")
            else
              LoginThrottle.record_attempt(ip)

              Helpers.audit_auth_action("Operator login failed",
                level: "warn",
                metadata: %{ip: ip, email: params["email"], reason: "operator_required"}
              )

              render_login(conn,
                form: to_form(params, as: :user),
                error: "This account does not have operator access."
              )
            end

          {:error, _reason} ->
            LoginThrottle.record_attempt(ip)

            Helpers.audit_auth_action("Operator login failed",
              level: "warn",
              metadata: %{ip: ip, email: params["email"], reason: "invalid_credentials"}
            )

            render_login(conn,
              form: to_form(params, as: :user),
              error: "Email or password is invalid."
            )
        end
    end
  end

  def create(conn, _params) do
    render_login(conn, form: to_form(%{}, as: :user), error: "Email and password are required.")
  end

  def delete(conn, _params) do
    Helpers.audit_auth_action("Operator logged out",
      metadata: %{ip: client_ip(conn)}
    )

    conn
    |> OperatorAuth.log_out()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/login")
  end

  defp render_login(conn, opts) do
    throttle = Keyword.get(opts, :throttle, LoginThrottle.state(client_ip(conn)))

    render(conn, :new,
      form: Keyword.fetch!(opts, :form),
      error: Keyword.get(opts, :error),
      expired_reason: Keyword.get(opts, :expired_reason),
      operator_exists?: Accounts.operator_user_exists?(),
      throttle: throttle,
      session_max_age_seconds: OperatorAuth.session_max_age_seconds(),
      idle_timeout_seconds: OperatorAuth.idle_timeout_seconds()
    )
  end

  defp client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
