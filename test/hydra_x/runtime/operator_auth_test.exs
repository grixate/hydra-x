defmodule HydraX.Runtime.OperatorAuthTest do
  use HydraX.DataCase

  alias HydraX.Runtime
  alias HydraX.Security.LoginThrottle
  alias HydraX.Safety

  test "operator password can be stored and authenticated" do
    Runtime.ensure_default_agent!()

    refute Runtime.operator_password_configured?()
    assert {:error, :not_configured} = Runtime.authenticate_operator("wrong")

    assert {:ok, secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    assert secret.password_hash
    assert secret.password_salt
    assert Runtime.operator_password_configured?()
    assert :ok = Runtime.authenticate_operator("hydra-password-123")
    assert {:error, :unauthorized} = Runtime.authenticate_operator("bad-password")

    operator = Runtime.operator_status()
    assert operator.configured
    assert operator.password_age_days == 0
    refute operator.password_stale?
    assert operator.login_max_attempts == LoginThrottle.max_attempts()
    assert operator.login_window_seconds == LoginThrottle.window_seconds()
    assert operator.blocked_login_ips == 0

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.level == "info"
    assert event.message =~ "Configured operator password"
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

  defp restore_env(key, nil), do: Application.delete_env(:hydra_x, key)
  defp restore_env(key, value), do: Application.put_env(:hydra_x, key, value)
end
