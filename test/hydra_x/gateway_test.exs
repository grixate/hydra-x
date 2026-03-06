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
