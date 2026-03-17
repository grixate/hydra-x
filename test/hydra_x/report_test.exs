defmodule HydraX.ReportTest do
  use HydraX.DataCase

  alias HydraX.Memory
  alias HydraX.Report
  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraX.Telemetry

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

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Prioritize operator-ready report exports for memory ranking visibility.",
        importance: 0.92,
        metadata: %{
          "source_file" => "ops/reporting.md",
          "source_section" => "memory-ranking",
          "source_channel" => "webchat"
        },
        last_seen_at: DateTime.utc_now()
      })

    Runtime.refresh_agent_bulletin!(agent.id)

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
          "provider_message_id" => "slack-stream-1",
          "metadata" => %{
            "transport" => "slack_chat_update"
          },
          "reply_context" => %{
            "stream_message_id" => "slack-stream-1"
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
    assert snapshot.memory.embedding.total_count >= 1
    assert snapshot.default_agent.bulletin.content =~ "Prioritize operator-ready report exports"
    assert snapshot.default_agent.bulletin.top_memories != []

    assert Enum.any?(
             snapshot.default_agent.bulletin.top_memories,
             &(&1.content =~ "Prioritize operator-ready report exports" and
                 is_map(&1.score_breakdown) and &1.source_file == "ops/reporting.md")
           )

    assert Enum.any?(
             snapshot.memory.ranked_memories,
             &(&1.entry.content =~ "Prioritize operator-ready report exports" and
                 is_map(&1.score_breakdown))
           )

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

  test "snapshot and export include lease-owned scheduler skips" do
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

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Report Remote-Owned Job",
        kind: "backup",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("scheduled_job:#{job.id}",
               owner: "node:remote-report",
               ttl_seconds: 120
             )

    assert {:ok, _run} = Runtime.run_scheduled_job(job)

    snapshot = Report.snapshot()

    assert %{reason: "lease_owned_elsewhere", count: count} =
             Enum.find(
               snapshot.scheduler.skipped_reason_counts,
               &(&1.reason == "lease_owned_elsewhere")
             )

    assert count >= 1

    assert Enum.any?(
             snapshot.scheduler.lease_owned_skips,
             &(&1.metadata["lease_owner"] == "node:remote-report")
           )

    output_root =
      Path.join(
        System.tmp_dir!(),
        "hydra-x-report-skip-export-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(output_root) end)

    assert {:ok, export} = Report.export_snapshot(output_root)

    markdown = File.read!(export.markdown_path)
    json = File.read!(export.json_path)

    assert markdown =~ "Skip reasons: lease owned elsewhere="
    assert markdown =~ "Lease-Owned Skips"
    assert markdown =~ "Report Remote-Owned Job"
    assert markdown =~ "node:remote-report"
    assert json =~ "\"skipped_reason_counts\""
    assert json =~ "\"lease_owned_skips\""
    assert json =~ "node:remote-report"
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

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Keep report exports aligned with ranked memory provenance.",
        importance: 0.95,
        metadata: %{
          "source_file" => "ops/reporting.md",
          "source_section" => "exports",
          "source_channel" => "slack"
        },
        last_seen_at: DateTime.utc_now()
      })

    Runtime.refresh_agent_bulletin!(agent.id)

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
            "output_excerpt" => "2 memories",
            "tool_use_id" => "tool-recall-1",
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
            "replay_count" => 1,
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
            }
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

    {:ok, _compactor_checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "compactor", %{
        "level" => "hard",
        "summary" =>
          "Compacted the report export conversation around the operator's reporting goal.",
        "summary_source" => "provider",
        "supporting_memories" => [
          %{
            "id" => 999,
            "type" => "Goal",
            "content" => "Keep report exports aligned with ranked memory provenance.",
            "score" => 1.23,
            "reasons" => ["semantic overlap", "high importance"],
            "score_breakdown" => %{"semantic" => 0.82, "importance" => 0.41},
            "source_file" => "ops/reporting.md",
            "source_channel" => "slack"
          }
        ]
      })

    {:ok, streaming_conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Streaming Report Summary",
        external_ref: "C556"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(streaming_conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "streaming",
          "external_ref" => "C556",
          "provider_message_id" => "slack-stream-1",
          "metadata" => %{
            "transport" => "slack_chat_update"
          },
          "reply_context" => %{
            "stream_message_id" => "slack-stream-1"
          },
          "formatted_payload" => %{
            "chunk_count" => 3,
            "text" => "Live report stream preview"
          }
        }
      })

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "extension",
        "goal" => "Package the operator-visible extension rollout.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated",
        "result_refs" => %{
          "last_requested_action" => "enable_extension",
          "extension_enablement_status" => "approved_not_enabled"
        }
      })

    {:ok, promoted_memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Treat approved research findings as live operator context.",
        importance: 0.83,
        metadata: %{"memory_scope" => "artifact_derived"},
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _research_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Publish the approved research operating context.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "result_refs" => %{"promoted_memory_ids" => [promoted_memory.id]}
      })

    {:ok, _publish_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Prepare a publish-ready autonomy summary for operators.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "result_refs" => %{"follow_up_work_item_ids" => [8_001]}
      })

    {:ok, publish_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Publish the finalized autonomy summary.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "result_refs" => %{
          "delivery" => %{
            "status" => "delivered",
            "channel" => "telegram",
            "target" => "ops-room",
            "metadata" => %{"provider_message_id" => "report-91"}
          }
        },
        "metadata" => %{
          "task_type" => "publish_summary",
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"},
          "assignment_resolution" => %{
            "strategy" => "role_capability_match",
            "resolved_agent_name" => "Report Agent",
            "resolved_agent_slug" => "report-agent",
            "reasons" => ["exact role match", "supports channel delivery", "queue clear"]
          },
          "follow_up_context" => %{
            "delivery_decisions" => [
              %{
                "type" => "DeliveryDecision",
                "content" =>
                  "Keep the previous publish path on the control plane until the summary is revised."
              }
            ]
          }
        }
      })

    {:ok, _delivery_brief} =
      Runtime.create_artifact(%{
        "work_item_id" => publish_item.id,
        "type" => "delivery_brief",
        "title" => "Publish-ready autonomy summary",
        "summary" => "Prepared channel delivery brief",
        "payload" => %{
          "publish_objective" =>
            "Revise the summary and route it through telegram for ops-room publication.",
          "destination_rationale" =>
            "Selected telegram -> ops-room using current publish policy at confidence 0.78 with ready posture.",
          "delivery_decision_snapshot" => %{
            "prior_summary" =>
              "Keep the previous publish path on the control plane until the summary is revised.",
            "comparison_summary" =>
              "Shifted delivery guidance from the prior path to the current recommendation."
          },
          "decision_confidence" => 0.78,
          "confidence_posture" => "ready",
          "recommended_actions" => [
            "Confirm the operator-ready summary with the on-call owner before publication."
          ]
        }
      })

    {:ok, _review_report} =
      Runtime.create_artifact(%{
        "work_item_id" => publish_item.id,
        "type" => "review_report",
        "title" => "Delivery review context",
        "summary" => "Reviewer compared the publish options.",
        "payload" => %{
          "delivery_decision_context" => [
            %{
              "content" =>
                "Route the revised summary through Slack because the operator requested a channel switch."
            }
          ]
        }
      })

    {:ok, _synthesis_ledger} =
      Runtime.create_artifact(%{
        "work_item_id" => publish_item.id,
        "type" => "decision_ledger",
        "title" => "Planner delivery synthesis",
        "summary" => "Planner compared delivery paths.",
        "payload" => %{
          "decision_type" => "delegation_synthesis",
          "summary_source" => "planner",
          "delivery_decisions" => [
            %{
              "content" =>
                "Keep the rerouted Slack plan because it preserves operator intent without reopening Telegram delivery."
            }
          ]
        }
      })

    {:ok, _degraded_publish_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Hold the degraded publish draft for review.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 99,
        "result_refs" => %{
          "degraded" => true,
          "delivery" => %{
            "status" => "draft",
            "degraded" => true,
            "channel" => "telegram",
            "target" => "ops-room",
            "reason" => "degraded_confidence_requires_review"
          }
        },
        "metadata" => %{
          "task_type" => "publish_summary",
          "degraded_execution" => true,
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"}
        }
      })

    {:ok, _degraded_research_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Queue constrained findings for reviewer follow-up.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "blocked",
        "approval_stage" => "validated",
        "review_required" => true,
        "priority" => 100,
        "result_refs" => %{
          "degraded" => true,
          "child_work_item_ids" => [8_201]
        },
        "metadata" => %{
          "degraded_execution" => true
        }
      })

    {:ok, _fallback_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Route the publish work through a fallback-capable operator.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "planned",
        "metadata" => %{
          "assignment_resolution" => %{
            "strategy" => "capability_fallback",
            "resolved_agent_name" => "Report Agent",
            "resolved_agent_slug" => "report-agent",
            "reasons" => ["supports channel delivery", "queue clear"]
          }
        }
      })

    {:ok, _role_only_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Await a concrete autonomy assignment.",
        "assigned_role" => "operator",
        "status" => "planned"
      })

    {:ok, _publish_review_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Approve the degraded publish draft after review.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 95,
        "result_refs" => %{"degraded" => true},
        "metadata" => %{
          "task_type" => "publish_approval",
          "degraded_execution" => true,
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"},
          "delivery_recovery" => %{
            "strategy" => "switch_delivery_channel",
            "recommended_channel" => "slack",
            "decision_basis" => "explicit_channel_signal"
          }
        }
      })

    {:ok, _rejected_publish_review_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Reject the degraded publish draft after review.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "failed",
        "approval_stage" => "validated",
        "priority" => 94,
        "result_refs" => %{
          "degraded" => true,
          "delivery" => %{
            "status" => "rejected",
            "degraded" => true,
            "channel" => "telegram",
            "target" => "ops-room",
            "reason" => "operator_rejected_delivery"
          }
        },
        "metadata" => %{
          "task_type" => "publish_approval",
          "degraded_execution" => true,
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"}
        }
      })

    {:ok, _rejected_publish_follow_up_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Queue a degraded publish replan after rejection.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 93,
        "result_refs" => %{
          "degraded" => true,
          "follow_up_work_item_ids" => [8_401],
          "follow_up_summary" => %{"count" => 1, "types" => ["replan"]},
          "delivery" => %{
            "status" => "skipped",
            "mode" => "report",
            "degraded" => true,
            "target" => "control-plane",
            "reason" => "internal_report_recovery"
          }
        },
        "metadata" => %{
          "task_type" => "publish_summary",
          "degraded_execution" => true,
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"}
        }
      })

    {:ok, _artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "patch_bundle",
        "title" => "Operator extension bundle",
        "summary" => "Packaged extension rollout",
        "payload" => %{
          "registration" => %{"enablement_status" => "approval_required"}
        }
      })

    {_work_item, _approval} =
      Runtime.approve_work_item!(work_item.id, %{
        "requested_action" => "enable_extension",
        "rationale" => "Operator approved the extension package for gated enablement."
      })

    {:ok, _unsafe_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Blocked publish escalation.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "failed",
        "autonomy_level" => "fully_automatic",
        "metadata" => %{"side_effect_class" => "external_delivery"},
        "result_refs" => %{
          "policy_failure" => %{
            "type" => "autonomy_level",
            "requested_level" => "fully_automatic"
          }
        }
      })

    {:ok, _budget_blocked_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Budget-blocked publish escalation.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "failed",
        "result_refs" => %{
          "policy_failure" => %{
            "type" => "token_budget",
            "limit_tokens" => 20,
            "used_tokens" => 20
          }
        }
      })

    {:ok, _replan_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Re-plan the constrained publish escalation.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "priority" => 99,
        "result_refs" => %{
          "follow_up_work_item_ids" => [9_201],
          "follow_up_summary" => %{"count" => 1, "types" => ["replan"]}
        }
      })

    {:ok, _job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Report autonomy sweep",
        kind: "autonomy",
        schedule_mode: "interval",
        interval_minutes: 60,
        enabled: true
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
    assert File.exists?(Path.join(export.bundle_dir, "memory.json"))
    assert File.exists?(Path.join(export.bundle_dir, "conversations.json"))
    assert File.exists?(Path.join(export.bundle_dir, "work_items.json"))
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
    assert File.read!(export.markdown_path) =~ "Autonomous Work Items"

    assert File.read!(export.markdown_path) =~ "active_jobs=1 unsafe_requests=2 budget_blocked=1"
    assert File.read!(export.markdown_path) =~ "auto_assigned="
    assert File.read!(export.markdown_path) =~ "fallback_assigned="
    assert File.read!(export.markdown_path) =~ "role_only_open="

    assert File.read!(export.markdown_path) =~ "approval=approved/enable_extension"
    assert File.read!(export.markdown_path) =~ "enablement=approved_not_enabled"
    assert File.read!(export.markdown_path) =~ "patch_bundle:approved/approved"
    assert File.read!(export.markdown_path) =~ "promoted=Decision:"
    assert File.read!(export.markdown_path) =~ "publish=queued 1"
    assert File.read!(export.markdown_path) =~ "publish=replan queued 1"
    assert File.read!(export.markdown_path) =~ "publish=delivered telegram -> ops-room"
    assert File.read!(export.markdown_path) =~ "assignment=report-agent:role_capability_match"

    assert File.read!(export.markdown_path) =~
             "publish_objective=Revise the summary and route it through telegram for ops-room publication."

    assert File.read!(export.markdown_path) =~
             "publish_prior_decision=Keep the previous publish path on the control plane until the summary is revised."

    assert File.read!(export.markdown_path) =~
             "publish_decision_comparison=Shifted delivery guidance from the prior path to the current recommendation."

    assert File.read!(export.markdown_path) =~
             "review_delivery_decision=Route the revised summary through Slack because the operator requested a channel switch."

    assert File.read!(export.markdown_path) =~
             "synthesis_delivery_decision=Keep the rerouted Slack plan because it preserves operator intent without reopening Telegram delivery."

    assert File.read!(export.markdown_path) =~
             "publish_rationale=Selected telegram -> ops-room using current publish policy at confidence 0.78 with ready posture."

    assert File.read!(export.markdown_path) =~ "publish_confidence=0.78:ready"

    assert File.read!(export.markdown_path) =~
             "publish_guidance=Confirm the operator-ready summary with the on-call owner before publication."

    assert File.read!(export.markdown_path) =~
             "publish=delivery_draft degraded telegram -> ops-room"

    assert File.read!(export.markdown_path) =~ "publish=degraded review queued 1"

    assert File.read!(export.markdown_path) =~
             "publish=degraded_delivery_awaiting_approval telegram -> ops-room"

    assert File.read!(export.markdown_path) =~ "recovery_switch_slack"
    assert File.read!(export.markdown_path) =~ "explicit_signal"

    assert File.read!(export.markdown_path) =~
             "publish=degraded_delivery_rejected telegram -> ops-room"

    assert File.read!(export.markdown_path) =~ "publish=delivery_internal"
    assert File.read!(export.markdown_path) =~ "control-plane"

    assert File.read!(export.markdown_path) =~ "level=fully_automatic"
    assert File.read!(export.markdown_path) =~ "effect=external_delivery"
    assert File.read!(export.markdown_path) =~ "policy=autonomy_fully_automatic"
    assert File.read!(export.markdown_path) =~ "policy=budget_tokens"
    assert File.read!(export.markdown_path) =~ "Treat approved research findings as live"
    assert File.read!(export.markdown_path) =~ "updates Slack thread"
    assert File.read!(export.markdown_path) =~ "stream_msg=slack-stream-1"
    assert File.read!(export.markdown_path) =~ "preview=Live report stream preview"
    assert File.read!(export.markdown_path) =~ "Top Bulletin Memories"

    assert File.read!(export.markdown_path) =~
             "Keep report exports aligned with ranked memory provenance."

    assert File.read!(export.markdown_path) =~ "channel=slack"
    assert File.read!(export.markdown_path) =~ "Top ranked active memories"

    work_items_json = File.read!(Path.join(export.bundle_dir, "work_items.json"))

    assert work_items_json =~ "\"delivery_decision_kind\": \"review\""
    assert work_items_json =~ "\"delivery_decision_snapshot\":"
    assert work_items_json =~ "\"assignment_resolution\":"
    assert work_items_json =~ "\"resolved_agent_slug\": \"report-agent\""

    assert work_items_json =~
             "\"delivery_decision_summary\": \"Route the revised summary through Slack because the operator requested a channel switch.\""

    assert work_items_json =~ "\"delivery_decision_kind\": \"synthesis\""

    assert work_items_json =~
             "\"delivery_decision_summary\": \"Keep the rerouted Slack plan because it preserves operator intent without reopening Telegram delivery.\""

    assert File.read!(export.markdown_path) =~ "ops/reporting.md"
    assert File.read!(export.markdown_path) =~ "breakdown="
    assert File.read!(export.markdown_path) =~ "Cluster Posture"
    assert File.read!(export.markdown_path) =~ "Coordination"
    assert File.read!(export.markdown_path) =~ "Coordination mode: local_single_node"
    assert File.read!(export.markdown_path) =~ "ctx=777.888/777.888"
    assert File.read!(export.markdown_path) =~ "chunks=2"
    assert File.read!(export.markdown_path) =~ "payload=channel=C555"
    assert File.read!(export.markdown_path) =~ "thread_ts=777.888"
    assert File.read!(export.markdown_path) =~ "execution=completed"
    assert File.read!(export.markdown_path) =~ "handoff=pending/stream_response/node:remote"
    assert File.read!(export.markdown_path) =~ "compaction=hard"
    assert File.read!(export.markdown_path) =~ "compaction_source=provider"
    assert File.read!(export.markdown_path) =~ "compaction_memories=1"

    assert File.read!(export.markdown_path) =~
             "pending_response=mock:Captured provider reply waiting for replay."

    assert File.read!(export.markdown_path) =~ "stream_capture=mock:chunks=2"

    assert File.read!(export.markdown_path) =~
             "memory:memory_recall:completed:recalled 2 memories"

    assert File.read!(export.markdown_path) =~
             "provider:response_generation:completed:completed captured response [lifecycle=replayed, source=handoff_replay, replay=1, retry=completed/attempts=2/retries=1/source=handoff_replay, attempt_history=running@2026-03-11 10:40:00 UTC->completed@2026-03-11 10:41:00 UTC]"

    assert File.read!(export.markdown_path) =~
             "skill:Apply enabled skill guidance:completed:Matched 1 skill hints [source=skill_context, retry=completed/attempts=1/source=skill_context]"

    assert File.read!(export.json_path) =~ "\"generated_at\""
    assert File.read!(export.json_path) =~ "\"last_delivery\""
    assert File.read!(export.json_path) =~ "\"ranked_memories\""
    assert File.read!(export.json_path) =~ "\"score_breakdown\""
    assert File.read!(export.json_path) =~ "\"source_section\""
    assert File.read!(export.json_path) =~ "\"skills\""
    assert File.read!(export.json_path) =~ "\"top_memories\""
    assert File.read!(export.json_path) =~ "\"work_items\""
    assert File.read!(export.json_path) =~ "\"active_autonomy_job_count\": 1"
    assert File.read!(export.json_path) =~ "\"unsafe_request_count\": 2"
    assert File.read!(export.json_path) =~ "\"budget_blocked_count\": 1"
    assert File.read!(export.json_path) =~ "\"auto_assigned_count\":"
    assert File.read!(export.json_path) =~ "\"capability_fallback_count\":"
    assert File.read!(export.json_path) =~ "\"role_only_open_count\":"

    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~
             "\"skill_requirement_count\""

    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~ "\"mcp_action_count\""
    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~ "\"search_docs\""
    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~ "\"top_memories\""
    assert File.read!(Path.join(export.bundle_dir, "agents.json")) =~ "\"ops/reporting.md\""
    assert File.read!(Path.join(export.bundle_dir, "channels.json")) =~ "\"streaming_count\""
    assert File.read!(Path.join(export.bundle_dir, "channels.json")) =~ "\"recent_streaming\""
    assert File.read!(Path.join(export.bundle_dir, "memory.json")) =~ "\"ranked_memories\""
    assert File.read!(Path.join(export.bundle_dir, "memory.json")) =~ "\"score_breakdown\""
    assert File.read!(Path.join(export.bundle_dir, "memory.json")) =~ "\"ops/reporting.md\""
    assert File.read!(export.markdown_path) =~ "Ingress replay:"
    assert File.read!(export.markdown_path) =~ "Ownership replay:"
    assert File.read!(export.markdown_path) =~ "Deferred delivery replay:"
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"channel_state\""
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"compaction\""

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~
             "\"summary_source\": \"provider\""

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~
             "\"supporting_memories\""

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"memory_recall\""
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"stream_capture\""
    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~ "\"retry_state\""
    assert File.read!(export.json_path) =~ "\"pending_ingress\""
    assert File.read!(export.json_path) =~ "\"ownership_handoffs\""
    assert File.read!(export.json_path) =~ "\"deferred_deliveries\""

    assert File.read!(Path.join(export.bundle_dir, "conversations.json")) =~
             "\"pending_response\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~
             "\"approval_stage\": \"operator_approved\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~ "\"patch_bundle\""
    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~ "\"promoted_memories\""
    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~ "\"publish_follow_up\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~
             "\"status\": \"delivered\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~
             "\"provider_message_id\": \"report-91\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~ "\"delivery\": {"

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~ "\"artifact_derived\""
    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~ "\"approvals\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~
             "\"requested_action\": \"enable_extension\""

    assert File.read!(Path.join(export.bundle_dir, "work_items.json")) =~
             "\"approved_not_enabled\""
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
