defmodule HydraX.TelegramWebhookTaskTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  test "telegram webhook task can send a delivery smoke test" do
    Mix.Task.reenable("hydra_x.telegram.webhook")

    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(self(), {:telegram_task_test, payload})
      {:ok, %{provider_message_id: 321}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    agent = create_agent()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Telegram.Webhook.run(["test", "777", "Task smoke test"])
      end)

    assert_receive {:telegram_task_test, %{content: "Task smoke test", external_ref: "777"}}
    assert output =~ "Delivered test message to 777"
    assert output =~ "provider_message_id"
  end

  test "telegram webhook task shows retryable failed deliveries" do
    Mix.Task.reenable("hydra_x.telegram.webhook")
    agent = create_agent()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        title: "Retry me",
        external_ref: "777"
      })

    {:ok, _updated} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "external_ref" => "777",
          "status" => "failed",
          "retry_count" => 2,
          "reason" => "timeout"
        }
      })

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Telegram.Webhook.run([])
      end)

    assert output =~ "Retryable failed deliveries: 1"
    assert output =~ "Failed conversation ##{conversation.id}: Retry me (retry 2)"
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Telegram Task Agent #{unique}",
        slug: "telegram-task-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-telegram-task-#{unique}"),
        description: "telegram task agent",
        is_default: false
      })

    agent
  end
end
