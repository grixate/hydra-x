defmodule HydraXWeb.SessionController do
  use HydraXWeb, :controller

  alias HydraX.Runtime
  alias HydraX.Runtime.Helpers
  alias HydraX.Runtime.OperatorSecret
  alias HydraXWeb.OperatorAuth

  @max_attempts 5
  @window_seconds 60

  def new(conn, params) do
    render(conn, :new,
      password_configured?: Runtime.operator_password_configured?(),
      reauth?: params["reauth"] == "1",
      changeset: OperatorSecret.changeset(%OperatorSecret{}, %{})
    )
  end

  def create(conn, %{"operator_secret" => params}) do
    ip = client_ip(conn)

    if rate_limited?(ip) do
      Helpers.audit_auth_action("Blocked operator login due to rate limit",
        level: "warn",
        metadata: %{ip: ip, window_seconds: @window_seconds, max_attempts: @max_attempts}
      )

      render(conn, :new,
        password_configured?: Runtime.operator_password_configured?(),
        reauth?: false,
        changeset:
          OperatorSecret.changeset(%OperatorSecret{}, %{})
          |> Ecto.Changeset.add_error(:password, "too many attempts, try again later")
      )
    else
      case Runtime.authenticate_operator(params["password"] || "") do
        :ok ->
          clear_attempts(ip)

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
          record_attempt(ip)
          attempts = current_attempts(ip)

          Helpers.audit_auth_action("Operator login failed",
            level: "warn",
            metadata: %{ip: ip, attempts: attempts, window_seconds: @window_seconds}
          )

          render(conn, :new,
            password_configured?: true,
            reauth?: false,
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

  # -- Rate limiting --

  defp ensure_table do
    if :ets.whereis(:login_rate_limit) == :undefined do
      :ets.new(:login_rate_limit, [:set, :public, :named_table])
    end
  end

  defp rate_limited?(ip) do
    ensure_table()
    sweep_expired_entries()
    now = System.system_time(:second)

    case :ets.lookup(:login_rate_limit, ip) do
      [{^ip, attempts, window_start}] when now - window_start < @window_seconds ->
        attempts >= @max_attempts

      _ ->
        false
    end
  end

  # Remove expired entries to prevent unbounded ETS table growth.
  # Runs on every rate-limit check — cheap O(n) scan for a table that
  # will only ever have a handful of entries (one per distinct IP).
  defp sweep_expired_entries do
    now = System.system_time(:second)

    :ets.tab2list(:login_rate_limit)
    |> Enum.each(fn {ip, _attempts, window_start} ->
      if now - window_start >= @window_seconds do
        :ets.delete(:login_rate_limit, ip)
      end
    end)
  end

  defp record_attempt(ip) do
    ensure_table()
    now = System.system_time(:second)

    case :ets.lookup(:login_rate_limit, ip) do
      [{^ip, attempts, window_start}] when now - window_start < @window_seconds ->
        :ets.insert(:login_rate_limit, {ip, attempts + 1, window_start})

      _ ->
        :ets.insert(:login_rate_limit, {ip, 1, now})
    end
  end

  defp clear_attempts(ip) do
    ensure_table()
    :ets.delete(:login_rate_limit, ip)
  end

  defp current_attempts(ip) do
    ensure_table()

    case :ets.lookup(:login_rate_limit, ip) do
      [{^ip, attempts, _window_start}] -> attempts
      _ -> 0
    end
  end

  defp client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
