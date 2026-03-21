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

    Runtime.Jobs.record_scheduler_pass(:stale_work_item_claims, %{
      owner: "node:test",
      expired_count: 3,
      skipped_count: 1,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:assignment_recoveries, %{
      owner: "node:test",
      recovered_count: 1,
      executed_count: 1,
      queued_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:role_queue_dispatches, %{
      owner: "node:test",
      processed_count: 6,
      delegation_expanded_count: 1,
      delegation_deferred_count: 2,
      required_role_prioritized_count: 2,
      pressure_skipped_count: 2,
      remote_owned_count: 1,
      skipped_count: 2,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:work_item_replays, %{
      owner: "node:test",
      resumed_count: 5,
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

    assert Runtime.scheduler_status().stale_work_item_claims.expired_count == 3

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "node:test"
    assert html =~ "Ingress replay"
    assert html =~ "processed 2"
    assert html =~ "Stale claim cleanup"
    assert html =~ "Assignment recovery"
    assert html =~ "Role queue dispatch"
    assert html =~ "processed 6"
    assert html =~ "Work item replay"
    assert html =~ "resumed 5"
    assert html =~ "Ownership replay"
    assert html =~ "resumed 3"
    assert html =~ "Deferred delivery replay"
    assert html =~ "delivered 4"
  end

  test "health page shows autonomy posture", %{conn: conn} do
    agent =
      Runtime.ensure_default_agent!()
      |> then(fn current -> Runtime.get_agent!(current.id) end)

    local_owner = Runtime.coordination_status().owner

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
        "status" => "planned",
        "priority" => 93
      })

    {:ok, _extension_item} =
      Runtime.save_work_item(%{
        "kind" => "extension",
        "goal" => "Package the new autonomy extension.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 95
      })

    {:ok, _publish_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Publish the autonomy research summary.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "priority" => 96,
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
        "priority" => 94,
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
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"},
          "assignment_resolution" => %{
            "strategy" => "capability_fallback",
            "resolved_agent_name" => agent.name,
            "resolved_agent_slug" => agent.slug,
            "reasons" => ["supports channel delivery", "queue clear"]
          }
        }
      })

    {:ok, _role_only_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Await a concrete operator assignment.",
        "assigned_role" => "operator",
        "status" => "planned",
        "metadata" => %{"assignment_mode" => "role_claim"}
      })

    {:ok, _claimed_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Show released ownership on the health page.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "priority" => 100,
        "metadata" => %{
          "ownership" => %{
            "owner" => local_owner,
            "stage" => "completed",
            "active" => false
          }
        }
      })

    {:ok, remote_claimed_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Show remote ownership on the health page.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "claimed",
        "priority" => 99,
        "metadata" => %{
          "ownership" => %{
            "owner" => "node:remote-health",
            "stage" => "claimed_remote",
            "active" => true
          }
        }
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("work_item:#{remote_claimed_item.id}",
               owner: "node:remote-health",
               ttl_seconds: 60
             )

    on_exit(fn ->
      Runtime.release_lease("work_item:#{remote_claimed_item.id}", owner: "node:remote-health")
    end)

    {:ok, _stale_claimed_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Show stale ownership pressure on the health page.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "claimed",
        "priority" => 96,
        "metadata" => %{
          "ownership" => %{
            "owner" => local_owner,
            "stage" => "claimed",
            "active" => true
          }
        }
      })

    {:ok, _unsafe_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Blocked autonomy request.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "failed",
        "priority" => 98,
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
        "priority" => 97,
        "result_refs" => %{
          "policy_failure" => %{
            "type" => "token_budget",
            "limit_tokens" => 12,
            "used_tokens" => 12
          }
        }
      })

    {:ok, _queued_recovery_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Hold queued reassignment under recovery cooldown.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "planned",
        "priority" => 100,
        "metadata" => %{
          "assignment_recovery" => %{
            "queue_reason" => "worker_saturated",
            "queued_at" => "2026-03-18T10:00:00Z",
            "deferred_until" => "2026-03-18T10:15:00Z"
          }
        }
      })

    {:ok, _deferred_role_queue_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Keep deferred role-queued work visible in the health backlog.",
        "assigned_role" => "planner",
        "status" => "planned",
        "priority" => 92,
        "metadata" => %{
          "assignment_mode" => "role_claim",
          "delegation_role_urgency" => 2,
          "role_queue_dispatch" => %{
            "reason" => "worker_saturated",
            "deferred_until" => "2099-03-18T10:20:00Z"
          }
        }
      })

    {:ok, delegation_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Supervise a parallel delegation batch for operator-facing research.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "blocked",
        "execution_mode" => "delegate",
        "priority" => 100,
        "metadata" => %{
          "delegation_batch" => %{
            "mode" => "parallel",
            "expected_count" => 2,
            "roles" => ["researcher", "operator"],
            "items" => [
              %{
                "child_key" => "researcher-evidence-export",
                "goal" => "Assess operator-facing evidence exports.",
                "assigned_role" => "researcher",
                "status" => "quorum_skipped"
              },
              %{
                "child_key" => "operator-fallback-brief",
                "goal" => "Prepare an internal operator fallback brief.",
                "assigned_role" => "operator",
                "status" => "pending_dispatch"
              }
            ],
            "completion_quorum" => 1,
            "completion_role_requirements" => %{"operator" => 1},
            "role_quorum_met" => true,
            "quorum_met" => true,
            "quorum_skipped_count" => 1,
            "supervision_budget" => 2,
            "supervision_active_children" => 1,
            "expansion_count" => 1,
            "expansion_deferred_count" => 2,
            "last_deferred_at" => "2099-03-18T10:15:00Z",
            "last_expanded_at" => "2099-03-18T10:05:00Z",
            "expansion_deferred_until" => "2099-03-18T10:25:00Z",
            "expansion_deferred_reason" => "role_capacity_constrained",
            "expansion_capacity_score" => -2.5,
            "expansion_delay_seconds" => 15,
            "expansion_pressure_severity" => "medium",
            "expansion_pressure_snapshot" => %{
              "operator" => %{
                "pending_count" => 1,
                "idle_workers" => 0,
                "available_workers" => 1,
                "busy_workers" => 0,
                "saturated_workers" => 0,
                "urgent_queued_count" => 0,
                "urgent_deferred_count" => 0
              }
            }
          }
        }
      })

    {:ok, _delegation_child_two} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Prepare an internal operator fallback brief.",
        "assigned_role" => "operator",
        "status" => "completed",
        "priority" => 89,
        "parent_work_item_id" => delegation_parent.id,
        "metadata" => %{"delegation_batch_key" => "operator-fallback-brief"}
      })

    {:ok, missing_role_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Hold a delegation slot until an operator review is available.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "blocked",
        "execution_mode" => "delegate",
        "priority" => 88,
        "result_refs" => %{
          "follow_up_summary" => %{
            "count" => 2,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan", "review_guided_replan"],
            "entries" => [
              %{
                "work_item_id" => 74_101,
                "type" => "replan",
                "strategy" => "operator_guided_replan",
                "summary" => "Operator-guided recovery",
                "priority_boost" => 3
              },
              %{
                "work_item_id" => 74_102,
                "type" => "replan",
                "strategy" => "review_guided_replan",
                "summary" => "Reviewer-guided recovery",
                "priority_boost" => 2
              }
            ]
          }
        },
        "metadata" => %{
          "delegation_batch" => %{
            "mode" => "parallel",
            "expected_count" => 2,
            "roles" => ["researcher", "operator"],
            "items" => [
              %{
                "child_key" => "researcher-context-pass",
                "goal" => "Capture the remaining research context.",
                "assigned_role" => "researcher",
                "status" => "pending_dispatch"
              },
              %{
                "child_key" => "operator-review-pass",
                "goal" => "Wait for the operator review pass.",
                "assigned_role" => "operator",
                "status" => "pending_dispatch"
              }
            ],
            "completion_quorum" => 1,
            "completion_role_requirements" => %{"operator" => 1}
          }
        }
      })

    {:ok, _missing_role_child} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Capture the remaining research context.",
        "assigned_role" => "researcher",
        "status" => "planned",
        "priority" => 87,
        "parent_work_item_id" => missing_role_parent.id,
        "metadata" => %{"delegation_batch_key" => "researcher-context-pass"}
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
    assert html =~ "Auto-assigned"
    assert html =~ "Fallback assigned"
    assert html =~ "Role-only open"
    assert html =~ "Active claims"
    assert html =~ "Stale claims"
    assert html =~ "Remote claims"
    assert html =~ "Orphaned assignments"
    assert html =~ "Role backlog"
    assert html =~ "deferred 1"
    assert html =~ "Saturated workers"
    assert html =~ "Delegation batches"
    assert html =~ "required role gaps 1"
    assert html =~ "urgent batches 1"
    assert html =~ "0 queued · 1 deferred"
    assert html =~ "highest urgent role need 2"
    assert html =~ "Role queue backlog"
    assert html =~ "Worker pressure"
    assert html =~ "Delegation supervision"
    assert html =~ "queued"
    assert html =~ "shared backlog"
    assert html =~ "urgent backlog"
    assert html =~ "stale 1"
    assert html =~ "assignment recovery queued: worker saturated"
    assert html =~ "cooldown until 2026-03-18 10:15:00 UTC"
    assert html =~ delegation_parent.goal
    assert html =~ "delegation batch 2 · active 0 · terminal 2"
    assert html =~ "strategy ordered"
    assert html =~ "delegation roles researcher, operator"
    assert html =~ "completion quorum 1 met"
    assert html =~ "role quorum operator x1 met"
    assert html =~ "quorum skipped 1"
    assert html =~ "budget 2 · remaining 1"
    assert html =~ "batch budget 1 · remaining 0"
    assert html =~ "supervision budget 2 · active children 1"
    assert html =~ "urgent 1"
    assert html =~ "recovery mix operator-guided x1, review-guided x1"
    assert html =~ "required roles operator x1"
    assert html =~ "pressure h0 m1 l0"
    assert html =~ "repeat deferrals 1 · max 2"
    assert html =~ "pending 1 · active 1 · terminal 2"
    assert html =~ "expanded 1 · last expanded 2099-03-18 10:05:00 UTC"
    assert html =~ "deferred 2 · last deferred 2099-03-18 10:15:00 UTC"
    assert html =~ "expansion pressure operator x1 (urgent 0/0, sat 0, avail 1)"
    assert html =~ "expansion severity medium · delay 15s"
    assert html =~ "expansion deferred · cooldown until 2099-03-18 10:25:00 UTC"
    assert html =~ "Operator confirmed the rollout."
    assert html =~ "ownership #{local_owner} · completed"
    assert html =~ "ownership node:remote-health · claimed_remote"
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
          "follow_up_summary" => %{
            "count" => 1,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan"],
            "priority_boosts" => [3],
            "alternative_strategies" => ["narrow_delegate_batch"]
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ replan_parent.goal

    assert html =~
             "replan queued 1 (Operator-guided recovery; priority +3; alternatives Narrowed delegation batch)"
  end

  test "health page shows recovery strategy summaries for planner replans", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "plan",
        "goal" => "Retry the constrained planner branch with operator guidance.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "planned",
        "approval_stage" => "proposal_only",
        "metadata" => %{
          "preferred_recovery_strategy" => "operator_guided_replan",
          "recovery_strategy_behavior" => "operator_review_after_execution",
          "recovery_strategy_priority_boost" => 3,
          "recovery_strategy_alternatives" => ["narrow_delegate_batch"],
          "recovery_strategy_alternative_summaries" => ["Narrowed delegation batch"]
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ work_item.goal
    assert html =~ "Operator-guided recovery with narrowed delegation fallback"
    assert html =~ "preferred strategy operator-guided"
    assert html =~ "strategy behavior operator review after execution"
    assert html =~ "strategy priority +3"
    assert html =~ "alternative strategies Narrowed delegation batch"
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
          "delivery_decision_snapshot" => %{
            "prior_summary" =>
              "Keep the previous publish path on the control plane until stronger evidence is available.",
            "comparison_summary" => "Retained the prior delivery guidance."
          },
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
          "follow_up_work_item_ids" => [8_301, 8_302],
          "follow_up_summary" => %{
            "count" => 2,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan"],
            "entries" => [
              %{
                "work_item_id" => 8_301,
                "type" => "replan",
                "strategy" => "operator_guided_replan",
                "summary" => "Operator-guided recovery",
                "alternative_strategies" => ["narrow_delegate_batch"],
                "alternative_summaries" => ["Narrowed delegation batch"],
                "priority_boost" => 3
              },
              %{
                "work_item_id" => 8_302,
                "type" => "replan",
                "strategy" => "review_guided_replan",
                "summary" => "Reviewer-guided recovery",
                "priority_boost" => 2
              }
            ],
            "priority_boosts" => [3],
            "alternative_strategies" => ["narrow_delegate_batch"]
          },
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

    {:ok, _operator_follow_up} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Route the rejected delegation strategy through operator intervention.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "priority" => 91,
        "metadata" => %{
          "task_type" => "delegation_pressure_operator_follow_up",
          "reason" => "role_capacity_constrained",
          "constraint_strategy" =>
            "Reduce parallel fan-out, wait for healthier worker capacity, and re-plan the next delegation step around the constrained role.",
          "assignment_mode" => "role_claim"
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
             "decision comparison Retained the prior delivery guidance."

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

    assert html =~
             "replan queued 2 (Operator-guided recovery; priority +3; alternatives Narrowed delegation batch; +1 more: Reviewer-guided recovery)"

    assert html =~ "operator intervention prepared role_capacity_constrained"

    assert html =~
             "constraint strategy Reduce parallel fan-out, wait for healthier worker capacity, and re-plan the next delegation step around the constrained role."
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
