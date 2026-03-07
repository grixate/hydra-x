defmodule HydraXWeb.ConversationsLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  setup do
    test_pid = self()
    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(test_pid, {:telegram_retry, payload})
      {:ok, %{provider_message_id: 123}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    :ok
  end

  test "conversations page can retry a failed Telegram delivery", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

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
        external_ref: "901",
        title: "Telegram 901"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "assistant",
        content: "Retryable Telegram reply",
        metadata: %{}
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "status" => "failed",
          "external_ref" => "901",
          "reason" => ":timeout"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/conversations")

    view
    |> element(~s(button[phx-click="retry_delivery"][phx-value-id="#{conversation.id}"]))
    |> render_click()

    assert_receive {:telegram_retry, %{external_ref: "901", content: "Retryable Telegram reply"}}

    html = render(view)
    assert html =~ "Telegram delivery retried"
    assert html =~ "delivery delivered"
  end

  test "conversations page shows Telegram attachment metadata", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        external_ref: "902",
        title: "Telegram 902"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        content: "See attachment",
        metadata: %{
          "attachments" => [
            %{"kind" => "document", "file_name" => "spec.pdf"}
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/conversations")

    html = render(view)
    assert html =~ "document: spec.pdf"
  end

  test "conversations page can start and reply to a control-plane conversation", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, view, _html} = live(conn, ~p"/conversations")

    view
    |> form("form[phx-submit=\"start_conversation\"]", %{
      "conversation" => %{
        "agent_id" => to_string(agent.id),
        "channel" => "control_plane",
        "title" => "UI Chat",
        "message" => "Remember that the UI can drive conversations."
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Conversation started"
    assert html =~ "UI Chat"
    assert html =~ "Remember that the UI can drive conversations."

    [conversation | _] = Runtime.list_conversations(limit: 5)

    view
    |> form("form[phx-submit=\"send_reply\"]", %{
      "reply" => %{"message" => "What do you remember?"}
    })
    |> render_submit()

    refreshed = Runtime.get_conversation!(conversation.id)
    assert length(refreshed.turns) == 4

    html = render(view)
    assert html =~ "Reply sent"
    assert html =~ "Relevant memory"
  end
end
