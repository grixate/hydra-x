defmodule HydraXWeb.HealthLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraX.Security.LoginThrottle
  alias HydraX.Telemetry

  setup do
    install_root =
      Path.join(System.tmp_dir!(), "hydra-x-health-install-#{System.unique_integer([:positive])}")

    previous_install_root = System.get_env("HYDRA_X_INSTALL_ROOT")
    System.put_env("HYDRA_X_INSTALL_ROOT", install_root)

    on_exit(fn ->
      restore_env("HYDRA_X_INSTALL_ROOT", previous_install_root)
      File.rm_rf(install_root)
    end)

    :ok
  end

  test "health page can filter readiness warnings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/health")

    view
    |> form("form[phx-submit=\"filter_health\"]", %{
      "filters" => %{
        "search" => "password",
        "check_status" => "",
        "readiness_status" => "warn",
        "required_only" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Operator password configured"
    assert html =~ "Required blockers"
    assert html =~ "Next steps"
    refute html =~ "Primary provider configured"
  end

  test "health page shows operator login throttle policy", %{conn: conn} do
    LoginThrottle.reset!()
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Login throttle"
    assert html =~ "5 attempts per 60s window"
    assert html =~ "blocked IPs 1"
  end

  test "health page shows tool channel policy", %{conn: conn} do
    {:ok, _policy} =
      Runtime.save_tool_policy(%{
        "workspace_write_channels_csv" => "cli,control_plane",
        "http_fetch_channels_csv" => "cli,scheduler",
        "web_search_channels_csv" => "cli",
        "shell_command_channels_csv" => "cli"
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Tool channel policy"
    assert html =~ "write cli, control_plane"
    assert html =~ "http cli, scheduler"
    assert html =~ "shell cli"
  end

  test "health page shows scheduler routing replay summaries", %{conn: conn} do
    Runtime.Jobs.reset_scheduler_passes()

    on_exit(fn ->
      Runtime.Jobs.reset_scheduler_passes()
    end)

    Runtime.Jobs.record_scheduler_pass(:pending_ingress, %{
      owner: "node:test",
      processed_count: 2,
      skipped_count: 1,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:ownership_handoffs, %{
      owner: "node:test",
      resumed_count: 3,
      skipped_count: 1,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:deferred_deliveries, %{
      owner: "node:test",
      delivered_count: 4,
      skipped_count: 2,
      error_count: 1,
      results: []
    })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "node:test"
    assert html =~ "Ingress replay"
    assert html =~ "processed 2"
    assert html =~ "Ownership replay"
    assert html =~ "resumed 3"
    assert html =~ "Deferred delivery replay"
    assert html =~ "delivered 4"
  end

  test "health page shows autonomy posture", %{conn: conn} do
    agent =
      Runtime.ensure_default_agent!()
      |> then(fn current -> Runtime.get_agent!(current.id) end)

    {:ok, agent} = Runtime.save_agent(agent, %{"role" => "planner"})

    {:ok, agent} =
      Runtime.save_agent(agent, %{
        "capability_profile" => %{"side_effect_classes" => ["external_delivery"]}
      })

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Prepare autonomous research rollout.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "planned"
      })

    {:ok, extension_item} =
      Runtime.save_work_item(%{
        "kind" => "extension",
        "goal" => "Package the new autonomy extension.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {:ok, publish_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Publish the autonomy research summary.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "result_refs" => %{"follow_up_work_item_ids" => [7_001]}
      })

    {:ok, _publish_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Prepare the publish-ready summary for operators.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "result_refs" => %{
          "delivery" => %{
            "status" => "delivered",
            "channel" => "telegram",
            "target" => "ops-room",
            "metadata" => %{"provider_message_id" => "health-91"}
          }
        },
        "metadata" => %{
          "task_type" => "publish_summary",
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"}
        }
      })

    {:ok, _unsafe_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Blocked autonomy request.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "failed",
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
        "goal" => "Budget-blocked autonomy request.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "failed",
        "result_refs" => %{
          "policy_failure" => %{
            "type" => "token_budget",
            "limit_tokens" => 12,
            "used_tokens" => 12
          }
        }
      })

    {:ok, _job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Health autonomy sweep",
        kind: "autonomy",
        schedule_mode: "interval",
        interval_minutes: 60,
        enabled: true
      })

    {_updated, _record} =
      Runtime.approve_work_item!(work_item.id, %{
        "requested_action" => "promote_work_item",
        "rationale" => "Operator confirmed the rollout."
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Work graph posture"
    assert html =~ "Role coverage"
    assert html =~ "Recent work items"
    assert html =~ "Recent approvals"
    assert html =~ "Awaiting operator"
    assert html =~ "Extensions gated"
    assert html =~ "Autonomy jobs"
    assert html =~ "Unsafe requests"
    assert html =~ "Budget blocked"
    assert html =~ "Capability drift"
    assert html =~ "Operator confirmed the rollout."
    assert html =~ "Prepare autonomous research rollout."
    assert html =~ extension_item.goal
    assert html =~ publish_parent.goal
    assert html =~ "publish queued 1"
    assert html =~ "delivered telegram"
    assert html =~ "ops-room"
    assert html =~ "blocked autonomy fully_automatic"
    assert html =~ "budget tokens exhausted"
  end

  test "health page shows replan follow-up posture", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, replan_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Re-plan the constrained autonomy request.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "priority" => 99,
        "result_refs" => %{
          "follow_up_work_item_ids" => [7_701],
          "follow_up_summary" => %{"count" => 1, "types" => ["replan"]}
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ replan_parent.goal
    assert html =~ "replan queued 1"
  end

  test "health page shows degraded publish posture", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, degraded_research} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Queue constrained research for reviewer follow-up.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "blocked",
        "approval_stage" => "validated",
        "review_required" => true,
        "priority" => 100,
        "result_refs" => %{"degraded" => true, "child_work_item_ids" => [7_801]},
        "metadata" => %{"degraded_execution" => true}
      })

    {:ok, degraded_publish} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Hold the constrained publish draft for review.",
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
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"},
          "follow_up_context" => %{
            "delivery_decisions" => [
              %{
                "type" => "DeliveryDecision",
                "content" =>
                  "Keep the previous publish path on the control plane until stronger evidence is available."
              }
            ]
          }
        }
      })

    {:ok, _review_report} =
      Runtime.create_artifact(%{
        "work_item_id" => degraded_publish.id,
        "type" => "review_report",
        "title" => "Delivery review context",
        "summary" => "Reviewer compared external and internal delivery.",
        "payload" => %{
          "delivery_decision_context" => [
            %{
              "content" =>
                "Keep the report internal until the revised summary clears operator review for external publication."
            }
          ]
        }
      })

    {:ok, _synthesis_ledger} =
      Runtime.create_artifact(%{
        "work_item_id" => degraded_publish.id,
        "type" => "decision_ledger",
        "title" => "Planner delivery synthesis",
        "summary" => "Planner retained the internal fallback.",
        "payload" => %{
          "decision_type" => "delegation_synthesis",
          "summary_source" => "planner",
          "delivery_decisions" => [
            %{
              "content" =>
                "Retain the control-plane fallback because confidence is still too low for Telegram delivery."
            }
          ]
        }
      })

    {:ok, publish_review} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Approve the constrained publish draft after review.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 98,
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

    {:ok, _degraded_delivery_brief} =
      Runtime.create_artifact(%{
        "work_item_id" => degraded_publish.id,
        "type" => "delivery_brief",
        "title" => "Constrained publish brief",
        "summary" => "Prepared degraded publish draft",
        "payload" => %{
          "publish_objective" =>
            "Prepare an internal operator report for control-plane delivery until external delivery is safe again.",
          "destination_rationale" =>
            "Selected report -> control-plane using low confidence safeguard (internal-only fallback) at confidence 0.52 with requires_review posture.",
          "decision_confidence" => 0.52,
          "confidence_posture" => "requires_review",
          "recommended_actions" => [
            "Keep this brief on the control plane until stronger evidence and explicit approval restore external delivery."
          ]
        }
      })

    {:ok, _rejected_publish_review} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Reject the constrained publish draft after review.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "failed",
        "approval_stage" => "validated",
        "priority" => 97,
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

    {:ok, _rejected_publish_follow_up} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Queue a constrained publish replan after delivery rejection.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 100,
        "result_refs" => %{
          "degraded" => true,
          "follow_up_work_item_ids" => [8_301],
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

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ degraded_research.goal
    assert html =~ "degraded review queued 1"
    assert html =~ degraded_publish.goal
    assert html =~ "delivery degraded draft telegram"
    assert html =~ publish_review.goal
    assert html =~ "degraded delivery awaiting approval telegram"
    assert html =~ "recovery switch slack"
    assert html =~ "explicit-signal"

    assert html =~
             "objective Prepare an internal operator report for control-plane delivery until external delivery is safe again."

    assert html =~
             "prior decision Keep the previous publish path on the control plane until stronger evidence is available."

    assert html =~
             "review decision Keep the report internal until the revised summary clears operator review for external publication."

    assert html =~
             "synthesis decision Retain the control-plane fallback because confidence is still too low for Telegram delivery."

    assert html =~
             "rationale Selected report"

    assert html =~ "confidence 0.52 (requires_review)"
    assert html =~ "low confidence safeguard"
    assert html =~ "internal-only fallback"

    assert html =~
             "guidance Keep this brief on the control plane until stronger evidence and explicit approval restore external delivery."

    assert html =~ "delivery internal"
    assert html =~ "replan queued 1"
  end

  test "health page shows the unified effective policy surface", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Unified decision surface"
    assert html =~ "Provider route"
    assert html =~ "Budget routing"
    assert html =~ "Workload routing"
    assert html =~ "Tool access matrix"
  end

  test "health page shows provider capability summary", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "LLM adapter capabilities"
    assert html =~ "system-prompt"
    assert html =~ "mock"
  end

  test "health page shows secret storage posture", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _provider} =
      Runtime.save_provider_config(%{
        name: "Health Secret Provider",
        kind: "openai_compatible",
        base_url: "https://secret-health.test",
        api_key: "secret",
        model: "gpt-secret-health",
        enabled: false
      })

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        webhook_secret: "hook-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Secret posture"
    assert html =~ "provider"
    assert html =~ "encrypted"
    assert html =~ "key source"
  end

  test "health page shows operator auth audit summaries", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    Enum.each(
      [
        {"Operator login succeeded", "info", %{"ip" => "127.0.0.1"}},
        {"Operator login failed", "warn", %{"ip" => "127.0.0.1"}},
        {"Blocked sensitive action pending re-authentication", "warn", %{}},
        {"Operator session expired", "warn", %{"expired_by" => "idle_timeout"}}
      ],
      fn {message, level, metadata} ->
        {:ok, _event} =
          HydraX.Safety.log_event(%{
            agent_id: agent.id,
            category: "auth",
            level: level,
            message: message,
            metadata: metadata
          })
      end
    )

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Recent auth audit"
    assert html =~ "Sign-ins (24h)"
    assert html =~ "Reauth blocks"
    assert html =~ "Session expiries"
    assert html =~ "idle_timeout"
  end

  test "health page can export an operator report", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/health")

    view
    |> element(~s(button[phx-click="export_report"]))
    |> render_click()

    html = render(view)
    assert html =~ "Operator report exported"
    assert html =~ "hydra-x-report-"
    assert html =~ ".md"
    assert html =~ ".json"
  end

  test "health page shows verified backup inventory", %{conn: conn} do
    {:ok, manifest} = HydraX.Backup.create_bundle(HydraX.Config.backup_root())
    backups = Runtime.backup_status()

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Backup inventory"
    assert html =~ manifest["archive_path"]
    assert html =~ "archive verified"
    assert html =~ "verified #{backups.verified_count}"
  end

  test "health page shows memory conflict triage", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Daily cadence should win.",
        last_seen_at: DateTime.utc_now()
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Weekly cadence should win.",
        last_seen_at: DateTime.utc_now()
      })

    assert {:ok, _result} = Memory.conflict_memory!(source.id, target.id)

    {:ok, _ranked} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Observation",
        content: "Health should surface the top ranked active memories with provenance.",
        importance: 0.9,
        metadata: %{
          "source_file" => "ops/health.md",
          "source_section" => "memory-triage",
          "source_channel" => "slack"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Conflict review queue"
    assert html =~ "Embedding backend"
    assert html =~ "Fallback writes"
    assert html =~ "Top ranked active memories"
    assert html =~ "Conflicted"
    assert html =~ "Health should surface the top ranked active memories with provenance."
    assert html =~ "ops/health.md"
    assert html =~ "importance"
    assert html =~ ">2<"
  end

  test "health page shows recent telemetry summaries", %{conn: conn} do
    Telemetry.provider_request(:error, "Broken Provider", %{})
    Telemetry.gateway_delivery("telegram", :ok, %{})

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Recent telemetry events"
    assert html =~ "Broken Provider"
    assert html =~ "telegram"
  end

  test "health page shows Telegram delivery diagnostics", %{conn: conn} do
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
        title: "Delayed reply",
        external_ref: "999"
      })

    {:ok, _updated} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "external_ref" => "999",
          "status" => "dead_letter",
          "retry_count" => 1,
          "reason" => "timeout",
          "provider_message_ids" => [501, 502],
          "dead_lettered_at" => "2026-03-11T09:00:00Z",
          "formatted_payload" => %{"chunk_count" => 2}
        }
      })

    {:ok, streaming_conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        title: "Streaming Reply",
        external_ref: "1000"
      })

    {:ok, _updated} =
      Runtime.update_conversation_metadata(streaming_conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "external_ref" => "1000",
          "status" => "streaming",
          "provider_message_id" => 9001,
          "metadata" => %{
            "transport" => "telegram_message_edit"
          },
          "reply_context" => %{
            "stream_message_id" => 9001
          },
          "formatted_payload" => %{
            "chunk_count" => 3,
            "text" => "Streaming partial response"
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Retryable failed deliveries: 1"
    assert html =~ "Recent Telegram delivery failures"
    assert html =~ "Active Telegram streams"
    assert html =~ "Delayed reply"
    assert html =~ "Streaming Reply"
    assert html =~ "dead letter 1"
    assert html =~ "multipart 1"
    assert html =~ "streaming 1"
    assert html =~ "chunks 3"
    assert html =~ "transport telegram_message_edit"
    assert html =~ "edits Telegram message"
    assert html =~ "msg 9001"
    assert html =~ "stream msg 9001"
    assert html =~ "preview Streaming partial response"
    assert html =~ "msg ids 2"
  end

  test "health page shows Discord and Slack channel readiness", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-test-token",
        application_id: "discord-app",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, failed_slack} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Slack Failure",
        external_ref: "C777"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(failed_slack, %{
        "last_delivery" => %{
          "channel" => "slack",
          "external_ref" => "C777",
          "status" => "failed",
          "reason" => "thread timeout",
          "reply_context" => %{"thread_ts" => "123.456"}
        }
      })

    {:ok, streaming_slack} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Slack Stream",
        external_ref: "C778"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(streaming_slack, %{
        "last_delivery" => %{
          "channel" => "slack",
          "external_ref" => "C778",
          "status" => "streaming",
          "provider_message_id" => "slack-stream-1",
          "reply_context" => %{"stream_message_id" => "slack-stream-1"},
          "metadata" => %{"transport" => "slack_chat_update"},
          "formatted_payload" => %{
            "chunk_count" => 4,
            "text" => "Streaming thread preview"
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Additional channel readiness"
    assert html =~ "discord"
    assert html =~ "slack"
    assert html =~ "discord-app"
    assert html =~ "capabilities:"
    assert html =~ "patches Discord message"
    assert html =~ "updates Slack thread"
    assert html =~ "thread timeout"
    assert html =~ "thread 123.456"
    assert html =~ "streaming 1"
    assert html =~ "Active streams"
    assert html =~ "Slack Stream"
    assert html =~ "msg slack-stream-1"
    assert html =~ "stream msg slack-stream-1"
    assert html =~ "preview Streaming thread preview"
  end

  test "health page shows Webchat readiness", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        subtitle: "Public ingress",
        enabled: true,
        allow_anonymous_messages: false,
        session_max_age_minutes: 180,
        session_idle_timeout_minutes: 30,
        attachments_enabled: true,
        max_attachment_count: 2,
        max_attachment_size_kb: 256,
        default_agent_id: agent.id
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Additional channel readiness"
    assert html =~ "webchat"
    assert html =~ "/webchat"
    assert html =~ "policy: identity required"
    assert html =~ "max 180m"
    assert html =~ "idle 30m"
    assert html =~ "attachments 2x256KB"
    assert html =~ "transport session_pubsub"
    assert html =~ "publishes Webchat session previews"
  end

  test "health page shows MCP server registry health", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, server} =
      Runtime.save_mcp_server(%{
        name: "Docs MCP",
        transport: "stdio",
        command: "cat",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    [binding] = Runtime.list_agent_mcp_servers(agent.id)
    assert binding.mcp_server_config_id == server.id

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "MCP servers"
    assert html =~ "Docs MCP"
    assert html =~ "stdio"
    assert html =~ "healthy"
    assert html =~ "Agent MCP"
    assert html =~ agent.slug
  end

  test "health page shows cluster posture", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Cluster posture"
    assert html =~ "single_node"
    assert html =~ "sqlite_single_writer"
    assert html =~ "Persistence: sqlite"
    assert html =~ "Backup mode: bundled_database"
    assert html =~ "Coordination mode"
    assert html =~ "local_single_node"
  end

  test "health page shows open scheduler circuits", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Circuit Health Job",
        kind: "prompt",
        interval_minutes: 30,
        enabled: true,
        circuit_state: "open",
        consecutive_failures: 2,
        last_failure_reason: "provider offline"
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Open circuits"
    assert html =~ "Open scheduler circuits"
    assert html =~ "Circuit Health Job"
    assert html =~ "provider offline"
  end

  test "health page shows scheduler skip reasons and lease-owned skips", %{conn: conn} do
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
        name: "Health Remote-Owned Job",
        kind: "backup",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("scheduled_job:#{job.id}",
               owner: "node:remote-health",
               ttl_seconds: 120
             )

    assert {:ok, _run} = Runtime.run_scheduled_job(job)

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Recent skip reasons"
    assert html =~ "Lease owned elsewhere"
    assert html =~ "Lease-owned skips"
    assert html =~ "Health Remote-Owned Job"
    assert html =~ "node:remote-health"
  end

  test "health page shows default agent provider warmup readiness", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Warm Health Provider",
        kind: "openai_compatible",
        base_url: "https://health-provider.test",
        api_key: "secret",
        model: "gpt-health",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{"default_provider_id" => provider.id})

    {:ok, _agent, _status} =
      Runtime.warm_agent_provider_routing(agent.id,
        request_fn: fn _opts ->
          {:ok,
           %{
             status: 200,
             body: %{
               "choices" => [
                 %{
                   "message" => %{"content" => "OK", "tool_calls" => nil},
                   "finish_reason" => "stop"
                 }
               ]
             }
           }}
        end
      )

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Default agent provider route warmed"
    assert html =~ "hydra-primary: Warm Health Provider via agent_default"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
