defmodule HydraX.ConversationsTaskTest do
  use HydraX.DataCase

  alias HydraX.Memory
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

    assert_receive {:telegram_retry, %{chat_id: "777", text: "Retry from Mix task"}}

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert refreshed.metadata["last_delivery"]["retry_count"] == 1
  end

  test "conversation task retries a failed Slack delivery" do
    Mix.Task.reenable("hydra_x.conversations")

    previous = Application.get_env(:hydra_x, :slack_deliver)

    Application.put_env(:hydra_x, :slack_deliver, fn payload ->
      send(self(), {:slack_retry, payload})
      {:ok, %{provider_message_id: "slack-321"}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :slack_deliver, previous)
      else
        Application.delete_env(:hydra_x, :slack_deliver)
      end
    end)

    agent = create_agent()

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
        external_ref: "C777",
        title: "Slack 777"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "assistant",
        content: "Retry from Mix task over Slack",
        metadata: %{}
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "failed",
          "external_ref" => "C777",
          "reason" => "timeout"
        }
      })

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["retry-delivery", to_string(conversation.id)])
      end)

    assert output =~ "Retried slack delivery"
    assert_receive {:slack_retry, %{channel: "C777", text: "Retry from Mix task over Slack"}}

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

  test "conversation task shows deferred ownership when sending to a remotely owned conversation" do
    Mix.Task.reenable("hydra_x.conversations")
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Deferred Task Chat"
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}",
               owner: "node:remote",
               ttl_seconds: 60
             )

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run([
          "send",
          to_string(conversation.id),
          "Forward this to the remote owner."
        ])
      end)

    assert output =~ "conversation=#{conversation.id}"
    assert output =~ "Conversation ownership is held by node:remote"

    [turn] = Runtime.list_turns(conversation.id)
    assert turn.content == "Forward this to the remote owner."
    assert turn.metadata["deferred_to_owner"] == "node:remote"
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
        metadata: %{
          "attachments" => [
            %{
              "kind" => "document",
              "file_name" => "spec.pdf",
              "download_ref" => "https://example.test/spec.pdf"
            }
          ]
        }
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "dead_letter",
          "external_ref" => "C4242",
          "provider_message_id" => "4242.111",
          "provider_message_ids" => ["4242.111", "4242.112"],
          "retry_count" => 2,
          "reason" => "thread timeout",
          "dead_lettered_at" => "2026-03-11T11:00:00Z",
          "attempt_history" => [
            %{
              "status" => "failed",
              "reason" => "thread timeout",
              "retry_count" => 1,
              "recorded_at" => "2026-03-11T10:30:00Z",
              "reply_context" => %{"thread_ts" => "123.456"}
            },
            %{
              "status" => "dead_letter",
              "reason" => "thread timeout",
              "retry_count" => 2,
              "recorded_at" => "2026-03-11T11:00:00Z",
              "reply_context" => %{"thread_ts" => "123.456"}
            }
          ],
          "formatted_payload" => %{
            "channel" => "C4242",
            "thread_ts" => "123.456",
            "chunk_count" => 2,
            "text" => "Transcript body"
          },
          "reply_context" => %{
            "thread_ts" => "123.456",
            "source_message_id" => "123.456"
          }
        }
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "completed",
        "ownership" => %{
          "mode" => "database_lease",
          "owner" => "node:test",
          "stage" => "idle"
        },
        "provider" => "mock",
        "tool_rounds" => 1,
        "handoff" => %{
          "status" => "pending",
          "waiting_for" => "stream_response",
          "owner" => "node:remote"
        },
        "pending_response" => %{
          "content" => "Captured provider reply waiting for replay.",
          "metadata" => %{"provider" => "mock"}
        },
        "stream_capture" => %{
          "content" => "Partial streamed transcript preview",
          "chunk_count" => 2,
          "provider" => "mock",
          "captured_at" => "2026-03-11T10:45:00Z"
        },
        "tool_cache_scope_turn_id" => 88,
        "recovery_lineage" => %{
          "turn_scope_id" => 88,
          "recovery_count" => 1,
          "cache_hits" => 1,
          "cache_misses" => 0
        },
        "steps" => [
          %{
            "id" => "tool-1-skill_inspect",
            "kind" => "skill",
            "name" => "skill_inspect",
            "status" => "completed",
            "summary" => "inspected 1 skills",
            "output_excerpt" => "1 skills",
            "owner" => "channel",
            "lifecycle" => "cached",
            "result_source" => "cache",
            "idempotency_key" => "tool-1-skill_inspect",
            "tool_use_id" => "tool-skill-1",
            "replay_count" => 1,
            "retry_state" => %{
              "attempt_count" => 2,
              "retry_count" => 1,
              "last_status" => "cached",
              "result_source" => "cache"
            },
            "attempt_history" => [
              %{"status" => "running", "at" => "2026-03-11T10:40:00Z"},
              %{"status" => "completed", "at" => "2026-03-11T10:41:00Z"}
            ],
            "cache_scope_turn_id" => 88,
            "cache_recorded_at" => "2026-03-11T10:41:00Z",
            "replay_provenance" => %{"result_source" => "fresh", "replayed" => false}
          },
          %{
            "id" => "provider-final",
            "kind" => "provider",
            "name" => "response_generation",
            "status" => "completed",
            "summary" => "completed captured response",
            "owner" => "channel",
            "lifecycle" => "replayed",
            "result_source" => "handoff_replay",
            "replay_count" => 1,
            "retry_state" => %{
              "attempt_count" => 2,
              "retry_count" => 1,
              "last_status" => "completed",
              "result_source" => "handoff_replay"
            },
            "attempt_history" => [
              %{"status" => "running", "at" => "2026-03-11T10:42:00Z"},
              %{"status" => "completed", "at" => "2026-03-11T10:43:00Z"}
            ]
          }
        ],
        "execution_events" => [
          %{
            "phase" => "tool_result",
            "at" => DateTime.utc_now(),
            "details" => %{
              "summary" => "inspected 1 skills",
              "kind" => "tool",
              "name" => "skill_inspect",
              "lifecycle" => "cached",
              "result_source" => "cache",
              "tool_use_id" => "tool-skill-1",
              "cached" => true
            }
          },
          %{
            "phase" => "tool_cache_hit",
            "at" => DateTime.utc_now(),
            "details" => %{
              "summary" => "cache replay",
              "kind" => "tool",
              "name" => "cache_reuse",
              "lifecycle" => "cached",
              "result_source" => "cache",
              "cache_hits" => 1
            }
          }
        ]
      })

    Mix.Task.reenable("hydra_x.conversations")

    show_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["show", to_string(conversation.id)])
      end)

    assert show_output =~ "attachments=1"
    assert show_output =~ "owner=database_lease/node:test/idle"
    assert show_output =~ "delivery=slack:dead_letter"
    assert show_output =~ "delivery_reason=thread timeout"
    assert show_output =~ "delivery_provider_message_ids=2"
    assert show_output =~ "delivery_reply_context=123.456/123.456"
    assert show_output =~ "payload_preview={"
    assert show_output =~ "delivery_attempt\tdead_letter"
    assert show_output =~ "attachment\tturn=1\tdocument:spec.pdf"

    export_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["export", to_string(conversation.id)])
      end)

    assert export_output =~ "path="

    transcript_path =
      export_output
      |> String.split("\n", trim: true)
      |> Enum.find(&String.starts_with?(&1, "path="))
      |> String.replace_prefix("path=", "")

    transcript = File.read!(transcript_path)
    assert transcript =~ "## Delivery state"
    assert transcript =~ "### Delivery attempts"
    assert transcript =~ "### Native payload preview"
    assert transcript =~ "### Attachments"
    assert transcript =~ "document: spec.pdf"
    assert transcript =~ "thread timeout"
    assert transcript =~ "\"thread_ts\": \"123.456\""
    assert transcript =~ "## Execution checkpoint"
    assert transcript =~ "owner: database_lease · node:test · idle"
    assert transcript =~ "handoff: pending · stream_response · node:remote"
    assert transcript =~ "pending_response: mock · Captured provider reply waiting for replay."
    assert transcript =~ "stream_capture: mock · chunks 2 · 2026-03-11 10:45:00 UTC"
    assert transcript =~ "### Pending response snapshot"
    assert transcript =~ "### Partial stream capture"
    assert transcript =~ "Partial streamed transcript preview"
    assert transcript =~ "### Steps"
    assert transcript =~ "skill skill_inspect"
    assert transcript =~ "inspected 1 skills"
    assert transcript =~ "provider response_generation"
    assert transcript =~ "completed captured response"
    assert transcript =~ "tool_use_id: tool-skill-1"
    assert transcript =~ "retry: cached · attempts 2 · retries 1 · cache"
    assert transcript =~ "retry: completed · attempts 2 · retries 1 · handoff_replay"

    assert transcript =~
             "attempts: running@2026-03-11 10:40:00 UTC -> completed@2026-03-11 10:41:00 UTC"

    assert transcript =~
             "attempts: running@2026-03-11 10:42:00 UTC -> completed@2026-03-11 10:43:00 UTC"

    assert transcript =~ "result_source: cache"
    assert transcript =~ "lifecycle: cached"
    assert transcript =~ "result_source: handoff_replay"
    assert transcript =~ "lifecycle: replayed"
    assert transcript =~ "cache_scope_turn_id: 88"
    assert transcript =~ "cache_recorded_at: 2026-03-11 10:41:00 UTC"
    assert transcript =~ "replay_provenance: fresh"
    assert transcript =~ "recovery: turn 88; recoveries 1; cache hits 1; cache misses 0"
    assert transcript =~ "### Recent execution events"
    assert transcript =~ "kind: tool"
    assert transcript =~ "name: skill_inspect"
    assert transcript =~ "lifecycle: cached"
    assert transcript =~ "result_source: cache"
    assert transcript =~ "tool_use_id: tool-skill-1"
    assert transcript =~ "cached: yes"

    Mix.Task.reenable("hydra_x.conversations")

    archive_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["archive", to_string(conversation.id)])
      end)

    assert archive_output =~ "status=archived"
    assert Runtime.get_conversation!(conversation.id).status == "archived"
  end

  test "conversation task can show execution state" do
    Mix.Task.reenable("hydra_x.conversations")
    agent = create_agent()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Show Chat"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "deferred",
        "ownership" => %{
          "mode" => "local_process",
          "owner" => "node:test",
          "stage" => "deferred"
        },
        "provider" => "mock",
        "tool_rounds" => 1,
        "resumable" => true,
        "handoff" => %{
          "status" => "pending",
          "waiting_for" => "stream_response",
          "owner" => "node:remote"
        },
        "pending_response" => %{
          "content" => "Captured provider response waiting for replay.",
          "metadata" => %{"provider" => "mock"}
        },
        "stream_capture" => %{
          "content" => "Partial streamed response",
          "chunk_count" => 2,
          "provider" => "mock"
        },
        "tool_cache_scope_turn_id" => 77,
        "recovery_lineage" => %{
          "turn_scope_id" => 77,
          "recovery_count" => 1,
          "cache_hits" => 1,
          "cache_misses" => 0
        },
        "steps" => [
          %{
            "id" => "tool-1-mcp_probe",
            "kind" => "integration",
            "name" => "mcp_probe",
            "status" => "completed",
            "summary" => "probed 1 MCP bindings",
            "lifecycle" => "cached",
            "result_source" => "cache",
            "cached" => true,
            "tool_use_id" => "tool-mcp-1",
            "replay_count" => 1,
            "retry_state" => %{
              "attempt_count" => 2,
              "retry_count" => 1,
              "last_status" => "cached",
              "result_source" => "cache"
            }
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
            }
          }
        ],
        "execution_events" => [
          %{
            "phase" => "tool_result",
            "details" => %{
              "summary" => "probed 1 MCP bindings",
              "round" => 1,
              "kind" => "tool",
              "name" => "mcp_probe",
              "lifecycle" => "cached",
              "result_source" => "cache",
              "tool_use_id" => "tool-mcp-1",
              "cached" => true
            }
          },
          %{
            "phase" => "tool_cache_hit",
            "details" => %{
              "summary" => "cache replay",
              "round" => 1,
              "kind" => "tool",
              "name" => "cache_reuse",
              "lifecycle" => "cached",
              "result_source" => "cache",
              "cache_hits" => 1
            }
          },
          %{
            "phase" => "handoff_response_replayed",
            "details" => %{
              "summary" => "Completed a provider response captured before ownership handoff",
              "kind" => "provider",
              "name" => "response_generation",
              "lifecycle" => "replayed",
              "result_source" => "handoff_replay",
              "replayed" => true
            }
          },
          %{
            "phase" => "handoff_restart",
            "details" => %{
              "summary" => "Restarted execution after an unfinished ownership handoff",
              "waiting_for" => "stream_response",
              "captured_chars" => 25,
              "captured_chunks" => 2
            }
          }
        ]
      })

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["show", to_string(conversation.id)])
      end)

    assert output =~ "conversation=#{conversation.id}"
    assert output =~ "execution_status=deferred"
    assert output =~ "owner=local_process/node:test/deferred"
    assert output =~ "provider=mock"
    assert output =~ "handoff=pending/stream_response/node:remote"
    assert output =~ "pending_response=mock:Captured provider response waiting for replay."
    assert output =~ "stream_capture=mock:chunks=2"
    assert output =~ "stream_capture_preview=Partial streamed response"
    assert output =~ "cache_scope_turn_id=77"
    assert output =~ "recovery_lineage=turn:77 recoveries:1 cache_hits:1 cache_misses:0"
    assert output =~ "step\tintegration\tmcp_probe\tcompleted\tprobed 1 MCP bindings"
    assert output =~ "tool_use_id=tool-mcp-1"
    assert output =~ "retry_state=cached,attempts=2,retries=1,source=cache"

    assert output =~
             "step\tprovider\tresponse_generation\tcompleted\tcompleted captured response\treplayed\thandoff_replay"

    assert output =~ "retry_state=completed,attempts=2,retries=1,source=handoff_replay"

    assert output =~
             "event\ttool_result\tprobed 1 MCP bindings\t1\tkind=tool\tname=mcp_probe\tlifecycle=cached\tresult_source=cache\ttool_use_id=tool-mcp-1\tcached"

    assert output =~
             "event\ttool_cache_hit\tcache replay\t1\tkind=tool\tname=cache_reuse\tlifecycle=cached\tresult_source=cache"

    assert output =~ "cache_hits=1"

    assert output =~
             "event\thandoff_response_replayed\tCompleted a provider response captured before ownership handoff\t\tkind=provider\tname=response_generation\tlifecycle=replayed\tresult_source=handoff_replay"

    assert output =~ "\treplayed\t"

    assert output =~
             "event\thandoff_restart\tRestarted execution after an unfinished ownership handoff"

    assert output =~ "waiting_for=stream_response"
    assert output =~ "captured_chunks=2"
  end

  test "conversation task can filter archived conversations by status and search" do
    Mix.Task.reenable("hydra_x.conversations")
    agent = create_agent()

    {:ok, active} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Active Ops Thread"
      })

    {:ok, archived} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Archived Ops Thread"
      })

    Runtime.archive_conversation!(archived.id)
    assert Runtime.get_conversation!(active.id).status == "active"

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run([
          "--status",
          "archived",
          "--search",
          "Archived",
          "--limit",
          "10"
        ])
      end)

    assert output =~ "archived\tcontrol_plane\tArchived Ops Thread"
    refute output =~ "Active Ops Thread"
  end

  test "conversation task can review and reset compaction" do
    Mix.Task.reenable("hydra_x.conversations")
    agent = create_agent()
    Runtime.save_compaction_policy!(agent.id, %{"soft" => 4, "medium" => 8, "hard" => 12})

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Show supporting memories in compaction CLI output.",
        importance: 0.9,
        metadata: %{
          "source_file" => "ops/cli.md",
          "source_channel" => "cli"
        }
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "control_plane",
        title: "Compact Me"
      })

    Enum.each(1..12, fn index ->
      {:ok, _turn} =
        Runtime.append_turn(conversation, %{
          role: if(rem(index, 2) == 0, do: "assistant", else: "user"),
          content: "Compaction turn #{index}",
          metadata: %{}
        })
    end)

    compact_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["compact", to_string(conversation.id)])
      end)

    assert compact_output =~ "turn_count=12"
    assert compact_output =~ "level=hard"
    assert compact_output =~ "soft=4"
    assert compact_output =~ "medium=8"
    assert compact_output =~ "hard=12"
    assert compact_output =~ "summary_source="
    assert compact_output =~ "supporting_memories="

    Mix.Task.reenable("hydra_x.conversations")

    reset_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["reset-compact", to_string(conversation.id)])
      end)

    assert reset_output =~ "level=idle"
    assert Runtime.conversation_compaction(conversation.id).summary == nil
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
