defmodule HydraX.TelegramRuntimeTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  test "register_telegram_webhook stores registration metadata" do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Telegram Agent #{unique}",
        slug: "telegram-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-telegram-#{unique}"),
        description: "telegram runtime test agent",
        is_default: false
      })

    {:ok, telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        webhook_secret: "secret-123",
        enabled: false,
        default_agent_id: agent.id
      })

    request_fn = fn token, url, secret, _opts ->
      assert token == "test-token"
      assert url == HydraX.Config.telegram_webhook_url()
      assert secret == "secret-123"
      :ok
    end

    assert {:ok, updated} = Runtime.register_telegram_webhook(telegram, request_fn: request_fn)
    assert updated.enabled
    assert updated.webhook_url == HydraX.Config.telegram_webhook_url()
    assert updated.webhook_registered_at
  end
end
