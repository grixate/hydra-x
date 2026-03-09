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
    assert html =~ "Execution plan"
    assert html =~ "Execution events"
    assert html =~ "Tool-capable turn"
    assert html =~ "provider_requested"

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
    assert html =~ "Mock response"
    assert html =~ "status completed"
  end

  test "conversations page can rename and archive a conversation", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Rename Me"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "assistant",
        content: "Transcript body",
        metadata: %{}
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    view
    |> form("form[phx-submit=\"rename_conversation\"]", %{
      "rename" => %{"title" => "Renamed Chat"}
    })
    |> render_submit()

    assert Runtime.get_conversation!(conversation.id).title == "Renamed Chat"

    view
    |> element(~s(button[phx-click="archive_conversation"][phx-value-id="#{conversation.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Conversation archived"
    assert Runtime.get_conversation!(conversation.id).status == "archived"
  end

  test "conversations page can filter archived conversations by search", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _active} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Alpha Active"
      })

    {:ok, archived} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Beta Archived"
      })

    Runtime.archive_conversation!(archived.id)

    {:ok, view, _html} = live(conn, ~p"/conversations")

    view
    |> form("form[phx-submit=\"filter_conversations\"]", %{
      "filters" => %{"search" => "Beta", "status" => "archived", "channel" => "control_plane"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Beta Archived"
    refute html =~ "Alpha Active"
  end

  test "conversations page can review and reset compaction", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    Runtime.save_compaction_policy!(agent.id, %{"soft" => 4, "medium" => 8, "hard" => 12})

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Compaction UI"
      })

    Enum.each(1..12, fn index ->
      {:ok, _turn} =
        Runtime.append_turn(conversation, %{
          role: if(rem(index, 2) == 0, do: "assistant", else: "user"),
          content: "Conversation turn #{index}",
          metadata: %{}
        })
    end)

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    view
    |> element(~s(button[phx-click="review_compaction"][phx-value-id="#{conversation.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Conversation compaction reviewed"
    assert html =~ "12 turns"
    assert html =~ "Policy thresholds: soft 4"

    view
    |> element(~s(button[phx-click="reset_compaction"][phx-value-id="#{conversation.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Conversation summary reset"
    assert html =~ "No summary checkpoint yet"
  end
end
