defmodule HydraX.ReportTest do
  use HydraX.DataCase

  alias HydraX.Report
  alias HydraX.Telemetry
  alias HydraX.Safety
  alias HydraX.Runtime

  setup do
    install_root =
      Path.join(System.tmp_dir!(), "hydra-x-report-install-#{System.unique_integer([:positive])}")

    previous_install_root = System.get_env("HYDRA_X_INSTALL_ROOT")
    System.put_env("HYDRA_X_INSTALL_ROOT", install_root)

    on_exit(fn ->
      restore_env("HYDRA_X_INSTALL_ROOT", previous_install_root)
      File.rm_rf(install_root)
    end)

    :ok
  end

  test "snapshot includes default agent, readiness, and health data" do
    agent = Runtime.ensure_default_agent!()
    previous_request_fn = Application.get_env(:hydra_x, :mcp_http_request_fn)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      case opts[:url] do
        "https://mcp.example.test/actions" ->
          {:ok,
           %{
             status: 200,
             body: %{"actions" => [%{"name" => "search_docs"}, %{"name" => "get_status"}]}
           }}

        "https://mcp.example.test/health" ->
          {:ok, %{status: 200, body: %{"status" => "ok"}}}
      end
    end)

    on_exit(fn ->
      if previous_request_fn do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "report.md"), "# Report\n\nTrack ingest runs.")
    assert {:ok, _result} = Runtime.ingest_file(agent.id, Path.join(ingest_dir, "report.md"))

    skill_dir = Path.join([agent.workspace_root, "skills", "release-checks"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Release Checks\nsummary: Validate release readiness.\nversion: 2.0.0\ntags: release,checks\nrequires: release-window\n---\n# Release Checks\n\nValidate release readiness."
    )

    assert {:ok, _skills} = Runtime.refresh_agent_skills(agent.id)
    Telemetry.tool_execution("workspace_read", :error, %{})

    {:ok, _event} =
      Safety.log_event(%{
        agent_id: agent.id,
        category: "operator",
        level: "info",
        message: "Generated an audit-ready report"
      })

    assert {:ok, _mcp} =
             Runtime.save_mcp_server(%{
               name: "Docs MCP",
               transport: "http",
               url: "https://mcp.example.test",
               enabled: true
             })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert {:ok, %{count: 1}} = Runtime.list_agent_mcp_actions(agent.id, refresh: true)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      case opts[:url] do
        "https://mcp.example.test/actions" ->
          flunk("report snapshot should reuse cached MCP action catalogs")

        "https://mcp.example.test/health" ->
          {:ok, %{status: 200, body: %{"status" => "ok"}}}
      end
    end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Report Conversation",
        external_ref: "C999"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        content: "[Slack attachments: application/pdf]",
        metadata: %{
          "attachments" => [
            %{
              "kind" => "file",
              "file_name" => "report.pdf",
              "download_ref" => "https://slack.test/report.pdf"
            }
          ]
        }
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "delivered",
          "external_ref" => "C999",
          "provider_message_id" => "999.111",
          "provider_message_ids" => ["999.111", "999.222"],
          "retry_count" => 1,
          "attempt_history" => [
            %{"status" => "failed", "reason" => "thread timeout"},
            %{"status" => "delivered"}
          ],
          "formatted_payload" => %{
            "channel" => "C999",
            "thread_ts" => "123.456",
            "chunk_count" => 2,
            "text" => "Report reply"
          },
          "reply_context" => %{
            "thread_ts" => "123.456",
            "source_message_id" => "123.456"
          }
        }
      })

    {:ok, streaming_conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Streaming Export Conversation",
        external_ref: "C556"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(streaming_conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "streaming",
          "external_ref" => "C556",
          "metadata" => %{
            "transport" => "session_pubsub",
            "transport_topic" => "stream:preview:C556"
          },
          "formatted_payload" => %{
            "chunk_count" => 3,
            "text" => "Live report stream preview"
          }
        }
      })

    snapshot = Report.snapshot()

    assert snapshot.default_agent.id == agent.id
    assert is_list(snapshot.health_checks)
    assert is_map(snapshot.readiness)
    assert snapshot.provider.kind
    assert snapshot.install.public_url
    assert is_list(snapshot.conversations)
    assert is_list(snapshot.agents)
    assert is_map(snapshot.channels)
    assert is_map(snapshot.secrets)
    assert Enum.any?(snapshot.mcp, &(&1.name == "Docs MCP" and &1.status == :ok))
    assert Enum.any?(snapshot.agent_mcp, &(&1.agent_id == agent.id and &1.enabled_bindings == 1))

    assert Enum.any?(
             snapshot.agents,
             &(&1.id == agent.id and &1.mcp_count == 1 and &1.skill_requirement_count >= 1 and
                 &1.mcp_action_count == 2)
           )

    assert Enum.any?(
             snapshot.skills,
             &(&1.agent_id == agent.id and "release-window" in (&1.metadata["requires"] || []))
           )

    assert snapshot.cluster.mode == "single_node"
    assert snapshot.coordination.mode == "local_single_node"
    assert is_map(snapshot.incidents)
    assert is_list(snapshot.audit)
    assert Enum.any?(snapshot.ingest, &(&1.source_file == "report.md"))
    assert snapshot.observability.telemetry_summary.tool.error >= 1
    assert snapshot.secrets.total_records >= 0
    assert Enum.any?(snapshot.observability.telemetry.recent_events, &(&1.namespace == "tool"))
    assert Enum.any?(snapshot.audit, &(&1.category == "operator"))

    assert Enum.any?(
             snapshot.conversations,
             &(&1.metadata["last_delivery"]["reply_context"]["thread_ts"] == "123.456")
           )
  end

  test "snapshot includes scheduler routing summaries" do
    Runtime.Jobs.reset_scheduler_passes()

    on_exit(fn ->
      Runtime.Jobs.reset_scheduler_passes()
    end)

    Runtime.Jobs.record_scheduler_pass(:pending_ingress, %{
      owner: "node:report",
      processed_count: 1,
      skipped_count: 0,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:ownership_handoffs, %{
      owner: "node:report",
      resumed_count: 2,
      skipped_count: 1,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:deferred_deliveries, %{
      owner: "node:report",
      delivered_count: 3,
      skipped_count: 1,
      error_count: 1,
      results: []
    })

    snapshot = Report.snapshot()

    assert snapshot.scheduler.pending_ingress.processed_count == 1
    assert snapshot.scheduler.ownership_handoffs.resumed_count == 2
    assert snapshot.scheduler.deferred_deliveries.delivered_count == 3
  end

  test "export_snapshot writes markdown json and bundle exports" do
    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-report-export-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    agent = Runtime.ensure_default_agent!()
    previous_request_fn = Application.get_env(:hydra_x, :mcp_http_request_fn)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      case opts[:url] do
        "https://mcp.example.test/actions" ->
          {:ok, %{status: 200, body: %{"actions" => [%{"name" => "search_docs"}]}}}

        "https://mcp.example.test/health" ->
          {:ok, %{status: 200, body: %{"status" => "ok"}}}
      end
    end)

    on_exit(fn ->
      if previous_request_fn do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    skill_dir = Path.join([agent.workspace_root, "skills", "report-skill"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Report Skill\nsummary: Add reporting context.\nrequires: audit-log\n---\n# Report Skill\n\nAdd reporting context."
    )

    assert {:ok, _skills} = Runtime.refresh_agent_skills(agent.id)

    assert {:ok, _server} =
             Runtime.save_mcp_server(%{
               name: "Docs MCP",
               transport: "http",
               url: "https://mcp.example.test",
               enabled: true
             })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert {:ok, %{count: 1}} = Runtime.list_agent_mcp_actions(agent.id, refresh: true)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      case opts[:url] do
        "https://mcp.example.test/actions" ->
          flunk("report export should reuse cached MCP action catalogs")

        "https://mcp.example.test/health" ->
          {:ok, %{status: 200, body: %{"status" => "ok"}}}
      end
    end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Export Conversation",
        external_ref: "C555"
      })

    {:ok, _turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        content: "[Slack attachments: application/pdf]",
        metadata: %{
          "attachments" => [
            %{
              "kind" => "file",
              "file_name" => "export.pdf",
              "download_ref" => "https://slack.test/export.pdf"
            }
          ]
        }
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "delivered",
          "external_ref" => "C555",
          "provider_message_id" => "555.111",
          "provider_message_ids" => ["555.111", "555.222"],
          "retry_count" => 1,
          "attempt_history" => [
            %{"status" => "failed", "reason" => "thread timeout"},
            %{"status" => "delivered"}
          ],
          "formatted_payload" => %{
            "channel" => "C555",
            "thread_ts" => "777.888",
            "chunk_count" => 2,
            "text" => "Export reply"
          },
          "reply_context" => %{
            "thread_ts" => "777.888",
            "source_message_id" => "777.888"
          }
        }
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "completed",
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
          "content" => "Partial streamed report preview",
          "chunk_count" => 2,
          "provider" => "mock"
        },
        "steps" => [
          %{
            "id" => "tool-1-memory_recall",
            "kind" => "memory",
            "name" => "memory_recall",
            "status" => "completed",
            "summary" => "recalled 2 memories",
            "output_excerpt" => "2 memories"
          }
        ],
        "execution_events" => [
          %{
            "phase" => "tool_result",
            "at" => DateTime.utc_now(),
            "details" => %{"summary" => "recalled 2 memories"}
          }
        ]
      })

    {:ok, export} = Report.export_snapshot(output_root)

    assert File.exists?(export.markdown_path)
    assert File.exists?(export.json_path)
    assert File.dir?(export.bundle_dir)
    assert File.exists?(Path.join(export.bundle_dir, "manifest.json"))
    assert File.exists?(Path.join(export.bundle_dir, "agents.json"))
    assert File.exists?(Path.join(export.bundle_dir, "cluster.json"))
    assert File.exists?(Path.join(export.bundle_dir, "coordination.json"))
    assert File.exists?(Path.join(export.bundle_dir, "mcp.json"))
    assert File.exists?(Path.join(export.bundle_dir, "channels.json"))
    assert File.exists?(Path.join(export.bundle_dir, "secrets.json"))
    assert File.exists?(Path.join(export.bundle_dir, "agent_mcp.json"))
    assert File.exists?(Path.join(export.bundle_dir, "skills.json"))
    assert File.exists?(Path.join(export.bundle_dir, "conversations.json"))
    assert File.exists?(Path.join(export.bundle_dir, "incidents.json"))
    assert File.exists?(Path.join(export.bundle_dir, "audit.json"))
    assert File.read!(export.markdown_path) =~ "Hydra-X Operator Report"
    assert File.read!(export.markdown_path) =~ "Agent Runtime Snapshots"
    assert File.read!(export.markdown_path) =~ "skill_requires="
    assert File.read!(export.markdown_path) =~ "mcp_actions=1"
    assert File.read!(export.markdown_path) =~ "MCP Integrations"
    assert File.read!(export.markdown_path) =~ "Agent MCP Bindings"
    assert File.read!(export.markdown_path) =~ "Audit Trail"
    assert File.read!(export.markdown_path) =~ "attachments=1"
    assert File.read!(export.markdown_path) =~ "attempts=2"
    assert File.read!(export.markdown_path) =~ "msg_ids=2"
    assert File.read!(export.markdown_path) =~ "Readiness"
    assert File.read!(export.markdown_path) =~ "Total items:"
    assert File.read!(export.markdown_path) =~ "Required warnings:"
    assert File.read!(export.markdown_path) =~ "Next steps:"
    assert File.read!(export.markdown_path) =~ "Provider Route"
    assert File.read!(export.markdown_path) =~ "Secret Posture"
    assert File.read!(export.markdown_path) =~ "Operator Auth"
    assert File.read!(export.markdown_path) =~ "Channel Failure Summary"
    assert File.read!(export.markdown_path) =~ "Active streaming deliveries"
    assert File.read!(export.markdown_path) =~ "Cluster Posture"
    assert File.read!(export.markdown_path) =~ "Coordination"
    assert File.read!(export.markdown_path) =~ "Coordination mode: local_single_node"
    assert File.read!(export.markdown_path) =~ "ctx=777.888/777.888"
    assert File.read!(export.markdown_path) =~ "chunks=2"
    assert File.read!(export.markdown_path) =~ "payload=channel=C555"
    assert File.read!(export.markdown_path) =~ "thread_ts=777.888"
    assert File.read!(export.markdown_path) =~ "execution=completed"
    assert File.read!(export.markdown_path) =~ "handoff=pending/stream_response/node:remote"

    assert File.read!(export.markdown_path) =~
             "pending_response=mock:Captured provider reply waiting for replay."

    assert File.read!(export.markdown_path) =~ "stream_capture=mock:chunks=2"

    assert File.read!(export.markdown_path) =~
             "memory:memory_recall:completed:recalled 2 memories"

    assert File.read!(export.json_path) =~ "\"generated_at\""
    assert File.read!(export.json_path) =~ "\"last_delivery\""
    assert File.read!(export.json_path) =~ "\"skills\""

    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~
             "\"skill_requirement_count\""

    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~ "\"mcp_action_count\""
    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~ "\"search_docs\""
    assert File.read!(Path.join(export.bundle_dir, "channels.json")) =~ "\"streaming_count\""
    assert File.read!(Path.join(export.bundle_dir, "channels.json")) =~ "\"recent_streaming\""
    assert File.read!(export.markdown_path) =~ "Ingress replay:"
    assert File.read!(export.markdown_path) =~ "Ownership replay:"
    assert File.read!(export.markdown_path) =~ "Deferred delivery replay:"
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"channel_state\""
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"memory_recall\""
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"stream_capture\""
    assert File.read!(export.json_path) =~ "\"pending_ingress\""
    assert File.read!(export.json_path) =~ "\"ownership_handoffs\""
    assert File.read!(export.json_path) =~ "\"deferred_deliveries\""

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~
             "\"pending_response\""
  end

  test "export_snapshot includes stale streaming recovery markers" do
    output_root =
      Path.join(
        System.tmp_dir!(),
        "hydra-x-report-stale-stream-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(output_root) end)

    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Stale Streaming Report",
        external_ref: "C777"
      })

    {:ok, _user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Recover this stale report stream.",
        metadata: %{"source" => "test"}
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "resumable" => true,
        "stream_capture" => %{
          "content" => "Partial streamed report preview",
          "chunk_count" => 3,
          "provider" => "mock"
        },
        "updated_at" => DateTime.add(DateTime.utc_now(), -120, :second),
        "execution_events" => []
      })

    {:ok, export} = Report.export_snapshot(output_root)

    assert File.read!(export.markdown_path) =~ "resume_from=streaming"
    assert File.read!(export.markdown_path) =~ "stale_stream=yes"

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~
             "\"resume_stage\": \"streaming\""

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~
             "\"stale_stream\": true"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
