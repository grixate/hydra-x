defmodule HydraXWeb.AuthAPIController do
  use HydraXWeb, :controller

  alias HydraX.Accounts
  alias HydraX.Security.LoginThrottle
  alias HydraXWeb.OperatorAuth

  def login(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    ip = client_ip(conn)
    throttle = LoginThrottle.state(ip)

    cond do
      throttle.rate_limited? ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited", retry_after: throttle.retry_after_seconds})

      true ->
        case Accounts.authenticate_user(email, password) do
          {:ok, user} ->
            if Accounts.operator?(user) do
              LoginThrottle.clear_attempts(ip)

              conn
              |> OperatorAuth.log_in(user)
              |> json(%{data: %{authenticated: true}})
            else
              LoginThrottle.record_attempt(ip)

              conn
              |> put_status(:forbidden)
              |> json(%{error: "operator_required"})
            end

          {:error, _} ->
            LoginThrottle.record_attempt(ip)

            conn
            |> put_status(:unauthorized)
            |> json(%{error: "invalid_credentials"})
        end
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email_and_password_required"})
  end

  def status(conn, _params) do
    state = OperatorAuth.session_state(conn)

    json(conn, %{
      data: %{
        operator_configured: Accounts.operator_user_exists?(),
        authenticated: state.valid?,
        user_id: state.user_id
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
