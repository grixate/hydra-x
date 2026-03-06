defmodule HydraX.ConversationsTaskTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  test "conversation task retries a failed Telegram delivery" do
    Mix.Task.reenable("hydra_x.conversations")

    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(self(), {:telegram_retry, payload})
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

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        external_ref: "777",
        title: "Telegram 777"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "assistant",
        content: "Retry from Mix task",
        metadata: %{}
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "status" => "failed",
          "external_ref" => "777",
          "reason" => ":timeout"
        }
      })

    Mix.Tasks.HydraX.Conversations.run(["retry-delivery", to_string(conversation.id)])

    assert_receive {:telegram_retry, %{external_ref: "777", content: "Retry from Mix task"}}

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["retry_count"] == 1
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Conversation Task Agent #{unique}",
        slug: "conversation-task-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-conversations-#{unique}"),
        description: "conversation task test agent",
        is_default: false
      })

    HydraX.Budget.ensure_policy!(agent.id)
    agent
  end
end
