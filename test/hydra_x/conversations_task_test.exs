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

  test "conversation task can start and send control-plane messages" do
    Mix.Task.reenable("hydra_x.conversations")
    agent = create_agent()

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run([
          "start",
          "Remember that Codex can drive conversations from the CLI task.",
          "--agent",
          agent.slug,
          "--title",
          "Task Chat"
        ])
      end)

    assert output =~ "conversation="

    [conversation | _] = Runtime.list_conversations(agent_id: agent.id, limit: 5)
    assert conversation.title == "Task Chat"

    Mix.Task.reenable("hydra_x.conversations")

    send_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run([
          "send",
          to_string(conversation.id),
          "What do you remember?"
        ])
      end)

    assert send_output =~ "conversation=#{conversation.id}"

    refreshed = Runtime.get_conversation!(conversation.id)
    assert length(refreshed.turns) == 4
  end

  test "conversation task can archive and export transcripts" do
    Mix.Task.reenable("hydra_x.conversations")
    agent = create_agent()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Export Chat"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "assistant",
        content: "Exportable transcript body",
        metadata: %{}
      })

    export_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["export", to_string(conversation.id)])
      end)

    assert export_output =~ "path="

    Mix.Task.reenable("hydra_x.conversations")

    archive_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["archive", to_string(conversation.id)])
      end)

    assert archive_output =~ "status=archived"
    assert Runtime.get_conversation!(conversation.id).status == "archived"
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
