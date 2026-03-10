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

  test "sync_telegram_webhook_info persists pending updates and last error" do
    agent = create_agent()

    {:ok, telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    request_fn = fn token, _opts ->
      assert token == "test-token"

      {:ok,
       %{
         "url" => HydraX.Config.telegram_webhook_url(),
         "pending_update_count" => 3,
         "last_error_message" => "conflict"
       }}
    end

    assert {:ok, updated} = Runtime.sync_telegram_webhook_info(telegram, request_fn: request_fn)
    assert updated.webhook_pending_update_count == 3
    assert updated.webhook_last_error == "conflict"
    assert updated.webhook_last_checked_at
  end

  test "delete_telegram_webhook disables ingress while keeping credentials" do
    agent = create_agent()

    {:ok, telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    request_fn = fn token, _opts ->
      assert token == "test-token"
      :ok
    end

    assert {:ok, updated} = Runtime.delete_telegram_webhook(telegram, request_fn: request_fn)
    refute updated.enabled
    assert updated.bot_token == "test-token"
    assert updated.webhook_last_checked_at
  end

  test "telegram delivery smoke test routes through the adapter" do
    agent = create_agent()

    {:ok, telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn payload ->
      send(self(), {:telegram_test_delivery, payload})
      {:ok, %{provider_message_id: 456}}
    end

    assert {:ok, result} =
             Runtime.test_telegram_delivery(
               telegram,
               "4242",
               "Hydra-X smoke test",
               deliver: deliver
             )

    assert_receive {:telegram_test_delivery,
                    %{text: "Hydra-X smoke test", chat_id: "4242"}}

    assert result.metadata[:provider_message_id] == 456
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Telegram Agent #{unique}",
        slug: "telegram-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-telegram-#{unique}"),
        description: "telegram runtime test agent",
        is_default: false
      })

    agent
  end
end
