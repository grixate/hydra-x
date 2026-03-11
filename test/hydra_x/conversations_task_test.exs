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
            "replay_count" => 1
          }
        ],
        "execution_events" => [
          %{
            "phase" => "tool_result",
            "at" => DateTime.utc_now(),
            "details" => %{"summary" => "inspected 1 skills"}
          },
          %{
            "phase" => "tool_cache_hit",
            "at" => DateTime.utc_now(),
            "details" => %{"summary" => "cache replay", "cache_hits" => 1}
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
    assert transcript =~ "### Steps"
    assert transcript =~ "skill skill_inspect"
    assert transcript =~ "inspected 1 skills"
    assert transcript =~ "result_source: cache"
    assert transcript =~ "lifecycle: cached"
    assert transcript =~ "recovery: turn 88; recoveries 1; cache hits 1; cache misses 0"
    assert transcript =~ "### Recent execution events"

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
        "status" => "completed",
        "ownership" => %{
          "mode" => "local_process",
          "owner" => "node:test",
          "stage" => "idle"
        },
        "provider" => "mock",
        "tool_rounds" => 1,
        "resumable" => false,
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
            "replay_count" => 1
          }
        ],
        "execution_events" => [
          %{
            "phase" => "tool_result",
            "details" => %{"summary" => "probed 1 MCP bindings", "round" => 1}
          },
          %{
            "phase" => "tool_cache_hit",
            "details" => %{"summary" => "cache replay", "round" => 1, "cache_hits" => 1}
          }
        ]
      })

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.HydraX.Conversations.run(["show", to_string(conversation.id)])
      end)

    assert output =~ "conversation=#{conversation.id}"
    assert output =~ "execution_status=completed"
    assert output =~ "owner=local_process/node:test/idle"
    assert output =~ "provider=mock"
    assert output =~ "cache_scope_turn_id=77"
    assert output =~ "recovery_lineage=turn:77 recoveries:1 cache_hits:1 cache_misses:0"
    assert output =~ "step\tintegration\tmcp_probe\tcompleted\tprobed 1 MCP bindings"
    assert output =~ "event\ttool_result\tprobed 1 MCP bindings\t1"
    assert output =~ "event\ttool_cache_hit\tcache replay\t1\tcache_hits=1"
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
