defmodule HydraX.GatewayTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  test "telegram updates are routed into conversations and answered" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn payload ->
      send(self(), {:telegram_reply, payload})
      :ok
    end

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 42},
                   "text" => "Remember that Telegram ingress is now routed."
                 }
               },
               %{deliver: deliver}
             )

    assert_receive {:telegram_reply, %{external_ref: "42", content: content}}
    assert content =~ "Saved memory"

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    assert conversation.channel == "telegram"
    assert Runtime.list_turns(conversation.id) |> length() == 2

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["external_ref"] == "42"
  end

  test "telegram delivery failures are logged and persisted on the conversation" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    deliver = fn _payload ->
      {:error, :timeout}
    end

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 77},
                   "text" => "Record the failed Telegram delivery state."
                 }
               },
               %{deliver: deliver}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "failed"
    assert refreshed.metadata["last_delivery"]["reason"] =~ ":timeout"

    [event | _] = HydraX.Safety.recent_events(agent.id, 5)
    assert event.category == "gateway"
    assert event.message == "Telegram delivery failed"
  end

  test "failed Telegram deliveries can be retried later" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 88},
                   "text" => "Retry the Telegram delivery after failure."
                 }
               },
               %{deliver: fn _payload -> {:error, :timeout} end}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)

    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(self(), {:telegram_retry, payload})
      {:ok, %{provider_message_id: 99}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    assert {:ok, _updated} = HydraX.Gateway.retry_conversation_delivery(conversation)
    assert_receive {:telegram_retry, %{external_ref: "88", content: content}}
    assert content =~ "Mock response:"
    assert content =~ "Retry the Telegram delivery after failure."

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["retry_count"] == 1
    assert refreshed.metadata["last_delivery"]["metadata"]["provider_message_id"] == 99
  end

  test "telegram attachment messages preserve attachment metadata" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    assert :ok =
             HydraX.Gateway.dispatch_telegram_update(
               %{
                 "message" => %{
                   "chat" => %{"id" => 91},
                   "caption" => "See attached",
                   "document" => %{
                     "file_id" => "doc-1",
                     "file_unique_id" => "doc-uniq",
                     "file_name" => "spec.pdf",
                     "mime_type" => "application/pdf",
                     "file_size" => 1024
                   }
                 }
               },
               %{deliver: fn _payload -> :ok end}
             )

    [conversation] = Runtime.list_conversations(agent_id: agent.id, limit: 10)
    [user_turn | _] = Runtime.list_turns(conversation.id)

    assert user_turn.role == "user"
    assert user_turn.content == "See attached"

    assert [%{"kind" => "document", "file_name" => "spec.pdf"}] =
             user_turn.metadata["attachments"]
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Gateway Agent #{unique}",
        slug: "gateway-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-gateway-#{unique}"),
        description: "gateway test agent",
        is_default: false
      })

    HydraX.Budget.ensure_policy!(agent.id)
    agent
  end
end
