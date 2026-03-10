defmodule HydraXWeb.ConversationsLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  setup do
    test_pid = self()
    previous = Application.get_env(:hydra_x, :telegram_deliver)
    previous_slack = Application.get_env(:hydra_x, :slack_deliver)

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

      if previous_slack do
        Application.put_env(:hydra_x, :slack_deliver, previous_slack)
      else
        Application.delete_env(:hydra_x, :slack_deliver)
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

    assert_receive {:telegram_retry, %{chat_id: "901", text: "Retryable Telegram reply"}}

    html = render(view)
    assert html =~ "Telegram delivery retried"
    assert html =~ "delivery delivered"
  end

  test "conversations page can retry a failed Slack delivery", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    test_pid = self()

    Application.put_env(:hydra_x, :slack_deliver, fn payload ->
      send(test_pid, {:slack_retry, payload})
      {:ok, %{provider_message_id: "slack-retry-1"}}
    end)

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        external_ref: "C901",
        title: "Slack 901"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "assistant",
        content: "Retryable Slack reply",
        metadata: %{}
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "failed",
          "external_ref" => "C901",
          "reason" => "thread timeout"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/conversations")

    view
    |> element(~s(button[phx-click="retry_delivery"][phx-value-id="#{conversation.id}"]))
    |> render_click()

    assert_receive {:slack_retry, %{channel: "C901", text: "Retryable Slack reply"}}

    html = render(view)
    assert html =~ "Slack delivery retried"
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
            %{
              "kind" => "document",
              "file_name" => "spec.pdf",
              "download_ref" => "telegram:file-123"
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/conversations")

    html = render(view)
    assert html =~ "document: spec.pdf"
    assert html =~ "telegram:file-123"
  end

  test "conversations page shows delivery reply and thread context", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        external_ref: "C321",
        title: "Slack 321"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "delivered",
          "external_ref" => "C321",
          "provider_message_id" => "321.654",
          "formatted_payload" => %{
            "channel" => "C321",
            "thread_ts" => "123.456",
            "chunk_count" => 2,
            "text" => "Reply body"
          },
          "reply_context" => %{
            "thread_ts" => "123.456",
            "source_message_id" => "123.456"
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "thread 123.456"
    assert html =~ "source 123.456"
    assert html =~ "chunks 2"
    assert html =~ "Native payload preview"
    assert html =~ "&quot;channel&quot;: &quot;C321&quot;"
    assert html =~ "&quot;thread_ts&quot;: &quot;123.456&quot;"
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
    assert html =~ "completed"
    assert html =~ "Final response generated"

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

  test "conversations page shows recovered resumable execution state", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "webchat",
        title: "Recovered UI"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "interrupted",
        "resumable" => true,
        "current_step_id" => "provider-final",
        "current_step_index" => 0,
        "steps" => [
          %{
            "id" => "provider-final",
            "kind" => "provider",
            "label" => "Recover",
            "status" => "running"
          }
        ],
        "execution_events" => [
          %{
            "phase" => "recovered_after_restart",
            "at" => DateTime.utc_now(),
            "details" => %{"summary" => "Recovered 1 pending user turn(s) after channel restart"}
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "resumable"
    assert html =~ "current"
    assert html =~ "Recovered 1 pending user turn(s) after channel restart"
  end

  test "conversations page shows planner skill hints", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Skill Hints UI"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "planned",
        "plan" => %{
          "mode" => "tool_capable",
          "latest_message" => "Run deploy checks",
          "steps" => [
            %{
              "id" => "skill-context",
              "kind" => "skill",
              "label" => "Apply enabled skill guidance",
              "status" => "completed",
              "summary" => "Matched 1 skill hints",
              "output_excerpt" => "Deploy Checks"
            }
          ],
          "skill_hints" => [
            %{
              "slug" => "deploy-checks",
              "name" => "Deploy Checks",
              "reason" => "Run deployment verification steps [tags: deploy, release]"
            }
          ]
        },
        "steps" => [
          %{
            "id" => "skill-context",
            "kind" => "skill",
            "label" => "Apply enabled skill guidance",
            "status" => "completed",
            "summary" => "Matched 1 skill hints",
            "output_excerpt" => "Deploy Checks"
          }
        ],
        "execution_events" => []
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "Skill hints"
    assert html =~ "Deploy Checks"
    assert html =~ "deploy-checks"
    assert html =~ "Matched 1 skill hints"
  end

  test "conversations page shows step summaries, excerpts, and cached badges", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Step Details UI"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "completed",
        "current_step_id" => nil,
        "current_step_index" => nil,
        "steps" => [
          %{
            "id" => "tool-1-memory_recall",
            "kind" => "tool",
            "name" => "memory_recall",
            "status" => "completed",
            "summary" => "recalled 2 memories",
            "output_excerpt" => "2 memories",
            "attempt_count" => 2,
            "started_at" => DateTime.utc_now(),
            "completed_at" => DateTime.utc_now(),
            "cached" => true,
            "safety_classification" => "memory_read",
            "updated_at" => DateTime.utc_now()
          }
        ],
        "execution_events" => []
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "recalled 2 memories"
    assert html =~ "2 memories"
    assert html =~ "attempt 2"
    assert html =~ "cached"
    assert html =~ "memory_read"
    assert html =~ "started"
    assert html =~ "finished"
  end

  test "conversations page shows typed integration steps", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Integration Step UI"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "planned",
        "steps" => [
          %{
            "id" => "tool-1-mcp_probe",
            "kind" => "integration",
            "name" => "mcp_probe",
            "label" => "Probe MCP integrations",
            "status" => "pending",
            "reason" => "probe enabled MCP integrations"
          }
        ],
        "execution_events" => []
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "integration"
    assert html =~ "mcp_probe"
    assert html =~ "probe enabled MCP integrations"
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
    assert html =~ "tokens"
    assert html =~ "Policy thresholds: soft 4 or 80%"

    view
    |> element(~s(button[phx-click="reset_compaction"][phx-value-id="#{conversation.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Conversation summary reset"
    assert html =~ "No summary checkpoint yet"
  end
end
