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
          "status" => "dead_letter",
          "external_ref" => "C321",
          "provider_message_id" => "321.654",
          "provider_message_ids" => ["321.654", "321.655"],
          "retry_count" => 2,
          "reason" => "thread timeout",
          "dead_lettered_at" => "2026-03-11T10:00:00Z",
          "attempt_history" => [
            %{"status" => "failed", "reason" => "thread timeout", "retry_count" => 1},
            %{"status" => "dead_letter", "reason" => "thread timeout", "retry_count" => 2}
          ],
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
    assert html =~ "retry 2"
    assert html =~ "msg ids 2"
    assert html =~ "dead letter 2026-03-11T10:00:00Z"
    assert html =~ "Delivery diagnostics"
    assert html =~ "Native payload preview"
    assert html =~ "&quot;channel&quot;: &quot;C321&quot;"
    assert html =~ "&quot;thread_ts&quot;: &quot;123.456&quot;"
  end

  test "conversations page shows streaming delivery diagnostics", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "webchat",
        external_ref: "webchat-session-streaming-ui",
        title: "Streaming Delivery UI"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "webchat",
          "status" => "streaming",
          "external_ref" => "webchat-session-streaming-ui",
          "chunk_count" => 3,
          "metadata" => %{
            "streaming" => true,
            "provider" => "Mock Provider",
            "transport" => "session_pubsub",
            "transport_topic" => "webchat:session:webchat-session-streaming-ui"
          },
          "formatted_payload" => %{
            "session_id" => "webchat-session-streaming-ui",
            "text" => "Partial streamed delivery preview",
            "chunk_count" => 3
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "delivery streaming"
    assert html =~ "chunks 3"
    assert html =~ "Partial streamed delivery preview"
    assert html =~ "transport session_pubsub"
    assert html =~ "topic webchat:session:webchat-session-streaming-ui"
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
    assert html =~ "Owner:"
    assert html =~ "local_process"
    assert html =~ "provider_requested"
    assert html =~ "completed"

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
  end

  test "conversations page surfaces deferred ownership when replying", %{conn: conn} do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Deferred UI Chat"
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}",
               owner: "node:remote",
               ttl_seconds: 60
             )

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    view
    |> form("form[phx-submit=\"send_reply\"]", %{
      "reply" => %{"message" => "Hold this for the owner."}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Reply deferred: Conversation ownership is held by node:remote"
    assert html =~ "status deferred"
    assert html =~ "resumable"
    assert html =~ "node:remote"

    refreshed = Runtime.get_conversation!(conversation.id)
    [turn] = refreshed.turns
    assert turn.content == "Hold this for the owner."
    assert turn.metadata["deferred_to_owner"] == "node:remote"
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
        "recovery_lineage" => %{
          "turn_scope_id" => 42,
          "recovery_count" => 1,
          "cache_hits" => 0,
          "cache_misses" => 1
        },
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
    assert html =~ "Recovery lineage"
    assert html =~ "Recovered 1 pending user turn(s) after channel restart"
  end

  test "conversations page shows handoff and partial stream diagnostics", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "webchat",
        title: "Stream Handoff UI"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "deferred",
        "resumable" => true,
        "handoff" => %{
          "status" => "pending",
          "waiting_for" => "stream_response",
          "owner" => "node:remote"
        },
        "pending_response" => %{
          "content" => "Captured provider reply waiting for the new owner.",
          "metadata" => %{"provider" => "Mock Provider"}
        },
        "stream_capture" => %{
          "content" => "Partial streamed response from the previous owner.",
          "chunk_count" => 3,
          "provider" => "Mock Provider",
          "captured_at" => DateTime.utc_now()
        },
        "execution_events" => [
          %{
            "phase" => "handoff_restart",
            "at" => DateTime.utc_now(),
            "details" => %{
              "waiting_for" => "stream_response",
              "captured_chars" => 44,
              "captured_chunks" => 3
            }
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "Ownership handoff pending"
    assert html =~ "Pending provider response from Mock Provider"
    assert html =~ "Partial stream capture"
    assert html =~ "Partial streamed response from the previous owner."
    assert html =~ "chunks 3"
    assert html =~ "resumed after stream_response"
  end

  test "conversations page rebuilds streaming content from checkpoint snapshots", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "cli",
        title: "Streaming Snapshot UI"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "stream_capture" => %{
          "content" => "Partial streamed answer",
          "chunk_count" => 1,
          "provider" => "Mock Provider"
        },
        "execution_events" => []
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "streaming"
    assert html =~ "Partial streamed answer"

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "stream_capture" => %{
          "content" => "Partial streamed answer with more detail",
          "chunk_count" => 2,
          "provider" => "Mock Provider"
        },
        "execution_events" => []
      })

    send(view.pid, {:conversation_updated, conversation.id})

    html = render(view)
    assert html =~ "Partial streamed answer with more detail"
  end

  test "conversations page shows stale streaming recovery state", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "cli",
        title: "Stale Streaming Recovery UI"
      })

    {:ok, _user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Resume this stale stream.",
        metadata: %{"source" => "test"}
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "resumable" => true,
        "stream_capture" => %{
          "content" => "Partial streamed answer",
          "chunk_count" => 2,
          "provider" => "Mock Provider"
        },
        "updated_at" => DateTime.add(DateTime.utc_now(), -120, :second),
        "execution_events" => []
      })

    {:ok, view, _html} = live(conn, ~p"/conversations?conversation_id=#{conversation.id}")

    html = render(view)
    assert html =~ "replay streaming"
    assert html =~ "Stale streaming checkpoint detected"
    assert html =~ "Partial streamed answer"
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

  test "conversations page shows normalized lifecycle details for tool, provider, and skill steps",
       %{conn: conn} do
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
            "lifecycle" => "cached",
            "result_source" => "cache",
            "replay_count" => 1,
            "safety_classification" => "memory_read",
            "updated_at" => DateTime.utc_now()
          },
          %{
            "id" => "provider-final",
            "kind" => "provider",
            "name" => "response_generation",
            "status" => "completed",
            "summary" => "completed captured response",
            "lifecycle" => "replayed",
            "result_source" => "handoff_replay",
            "retry_state" => %{
              "attempt_count" => 2,
              "retry_count" => 1,
              "last_status" => "completed",
              "result_source" => "handoff_replay"
            },
            "attempt_history" => [
              %{"status" => "running", "at" => "2026-03-11T10:40:00Z"},
              %{"status" => "completed", "at" => "2026-03-11T10:41:00Z"}
            ]
          },
          %{
            "id" => "skill-context",
            "kind" => "skill",
            "label" => "Apply enabled skill guidance",
            "status" => "completed",
            "summary" => "Matched 1 skill hints",
            "result_source" => "skill_context",
            "retry_state" => %{
              "attempt_count" => 1,
              "last_status" => "completed",
              "result_source" => "skill_context"
            },
            "attempt_history" => [
              %{"status" => "completed", "at" => "2026-03-11T10:39:00Z"}
            ]
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
    assert html =~ "cache"
    assert html =~ "replay 1"
    assert html =~ "memory_read"
    assert html =~ "started"
    assert html =~ "finished"
    assert html =~ "response_generation"
    assert html =~ "completed captured response"
    assert html =~ "Retry state: completed"
    assert html =~ "source handoff_replay"
    assert html =~ "Attempts: running 10:40:00 -&gt; completed 10:41:00"
    assert html =~ "Apply enabled skill guidance"
    assert html =~ "Matched 1 skill hints"
    assert html =~ "source skill_context"
    assert html =~ "Attempts: completed 10:39:00"
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
