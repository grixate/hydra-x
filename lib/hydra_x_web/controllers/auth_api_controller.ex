defmodule HydraXWeb.AuthAPIController do
  use HydraXWeb, :controller

  alias HydraX.Runtime
  alias HydraX.Security.LoginThrottle
  alias HydraXWeb.OperatorAuth

  def login(conn, %{"password" => password}) when is_binary(password) do
    ip = client_ip(conn)
    throttle = LoginThrottle.state(ip)

    cond do
      throttle.rate_limited? ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited", retry_after: throttle.retry_after_seconds})

      true ->
        case Runtime.authenticate_operator(password || "") do
          :ok ->
            LoginThrottle.clear_attempts(ip)

            conn
            |> OperatorAuth.log_in()
            |> json(%{data: %{authenticated: true}})

          {:error, :not_configured} ->
            # No password configured — auto-login
            conn
            |> OperatorAuth.log_in()
            |> json(%{data: %{authenticated: true}})

          {:error, _} ->
            LoginThrottle.record_attempt(ip)

            conn
            |> put_status(:unauthorized)
            |> json(%{error: "invalid_password"})
        end
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "password_required"})
  end

  def status(conn, _params) do
    configured? = Runtime.operator_password_configured?()
    authenticated? = OperatorAuth.session_state(conn).valid?

    json(conn, %{
      data: %{
        password_configured: configured?,
        authenticated: not configured? or authenticated?
      }
    })
  end

  defp client_ip(conn) do
    forwarded = Plug.Conn.get_req_header(conn, "x-forwarded-for")

    case forwarded do
      [ip | _] -> ip |> String.split(",") |> List.first() |> String.trim()
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
