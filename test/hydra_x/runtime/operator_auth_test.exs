defmodule HydraX.Runtime.OperatorAuthTest do
  use HydraX.DataCase

  alias HydraX.Accounts
  alias HydraX.Runtime
  alias HydraX.Security.LoginThrottle
  alias HydraX.Safety

  test "first local operator configures the control plane" do
    Runtime.ensure_default_agent!()

    refute Runtime.operator_password_configured?()

    {:ok, %{user: user}} =
      Accounts.register_first_operator(%{
        "email" => "operator@test.example.com",
        "display_name" => "Operator",
        "password" => "hydra-password-123",
        "password_confirmation" => "hydra-password-123"
      })

    assert Accounts.operator?(user)
    assert Runtime.operator_password_configured?()

    operator = Runtime.operator_status()
    assert operator.configured
    assert operator.operator_email == user.email
    assert operator.login_max_attempts == LoginThrottle.max_attempts()
    assert operator.login_window_seconds == LoginThrottle.window_seconds()
    assert operator.blocked_login_ips == 0
  end

  test "operator status reflects configurable session policy" do
    previous_max = Application.get_env(:hydra_x, :operator_session_max_age_seconds)
    previous_idle = Application.get_env(:hydra_x, :operator_session_idle_timeout_seconds)

    Application.put_env(:hydra_x, :operator_session_max_age_seconds, 10 * 60 * 60)
    Application.put_env(:hydra_x, :operator_session_idle_timeout_seconds, 45 * 60)

    on_exit(fn ->
      restore_env(:operator_session_max_age_seconds, previous_max)
      restore_env(:operator_session_idle_timeout_seconds, previous_idle)
    end)

    operator = Runtime.operator_status()
    assert operator.session_max_age_seconds == 10 * 60 * 60
    assert operator.idle_timeout_seconds == 45 * 60
  end

  test "operator status summarizes recent auth audit activity" do
    agent = Runtime.ensure_default_agent!()

    Enum.each(
      [
        {"Operator login succeeded", "info", %{"ip" => "127.0.0.1"}},
        {"Operator login failed", "warn", %{"ip" => "127.0.0.1"}},
        {"Blocked operator login due to rate limit", "warn", %{"ip" => "127.0.0.1"}},
        {"Blocked sensitive action pending re-authentication", "warn", %{}},
        {"Operator session expired", "warn", %{"expired_by" => "idle_timeout"}}
      ],
      fn {message, level, metadata} ->
        {:ok, _event} =
          Safety.log_event(%{
            agent_id: agent.id,
            category: "auth",
            level: level,
            message: message,
            metadata: metadata
          })
      end
    )

    operator = Runtime.operator_status()

    assert operator.recent_login_success_count == 1
    assert operator.recent_login_failure_count == 1
    assert operator.recent_rate_limited_count == 1
    assert operator.recent_reauth_block_count == 1
    assert operator.recent_session_expiry_count == 1
    assert operator.last_session_expired_reason == "idle_timeout"
    assert Enum.any?(operator.recent_events, &(&1.message == "Operator session expired"))
  end

  defp restore_env(key, nil), do: Application.delete_env(:hydra_x, key)
  defp restore_env(key, value), do: Application.put_env(:hydra_x, key, value)
end
