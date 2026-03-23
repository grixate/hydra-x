defmodule HydraXWeb.AgentsLiveTest do
  use HydraXWeb.ConnCase
  @moduletag seed_default_agent: false

  alias HydraX.{Memory, Runtime}

  setup do
    on_exit(fn ->
      Runtime.list_agents()
      |> Enum.each(fn agent -> HydraX.Agent.ensure_stopped(agent) end)
    end)

    :ok
  end

  test "agents page can edit an agent and make it default", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Ops Agent",
        slug: "ops-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-ops-agent"),
        description: "before edit",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{agent.id}"]))
    |> render_click()

    view
    |> form(~s(form[phx-submit="save"]), %{
      "agent_profile" => %{
        "name" => "Ops Agent Updated",
        "slug" => "ops-agent",
        "role" => "planner",
        "workspace_root" => agent.workspace_root,
        "description" => "after edit",
        "is_default" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Agent updated"
    assert html =~ "Ops Agent Updated"
    assert html =~ "planner"
    assert html =~ "default"
    assert Runtime.get_default_agent().slug == "ops-agent"
  end

  test "agents page shows role capability, queue posture, and recent work items", %{conn: conn} do
    Runtime.Jobs.reset_scheduler_passes()

    on_exit(fn ->
      Runtime.Jobs.reset_scheduler_passes()
    end)

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Research Agent",
        slug: "research-agent",
        role: "researcher",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-research-agent"),
        description: "research",
        is_default: false
      })

    {:ok, _work_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Map the current operator-facing autonomy work.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "result_refs" => %{"promoted_memory_ids" => []}
      })

    {:ok, promoted_memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Use approved research findings as live operating context.",
        importance: 0.84,
        metadata: %{"memory_scope" => "artifact_derived"},
        last_seen_at: DateTime.utc_now()
      })

    [research_item | _] = Runtime.list_work_items(agent_id: agent.id, limit: 1)

    {:ok, _research_item} =
      Runtime.save_work_item(research_item, %{
        "result_refs" => %{"promoted_memory_ids" => [promoted_memory.id]}
      })

    {:ok, extension_item} =
      Runtime.save_work_item(%{
        "kind" => "extension",
        "goal" => "Package the operator-facing extension rollout.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "result_refs" => %{
          "last_requested_action" => "enable_extension",
          "extension_enablement_status" => "approved_not_enabled"
        }
      })

    {:ok, _artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => extension_item.id,
        "type" => "patch_bundle",
        "title" => "Extension bundle",
        "summary" => "Packaged autonomy extension"
      })

    {:ok, _publish_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Prepare a publish-ready summary for autonomy findings.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "completed",
        "approval_stage" => "operator_approved",
        "result_refs" => %{"follow_up_work_item_ids" => [9_001]}
      })

    {:ok, publish_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Publish the finalized summary for autonomy findings.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "completed",
        "approval_stage" => "validated",
        "result_refs" => %{
          "delivery" => %{
            "status" => "delivered",
            "channel" => "telegram",
            "target" => "ops-room",
            "metadata" => %{"provider_message_id" => "91"}
          }
        },
        "metadata" => %{
          "task_type" => "publish_summary",
          "delivery" => %{"mode" => "channel", "channel" => "telegram", "target" => "ops-room"},
          "assignment_resolution" => %{
            "strategy" => "role_capability_match",
            "resolved_agent_name" => "Research Agent",
            "resolved_agent_slug" => "research-agent",
            "reasons" => [
              "exact role match",
              "supports channel delivery",
              "pressure idle",
              "queue clear"
            ]
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

    {:ok, paused_researcher} =
      Runtime.save_agent(%{
        "role" => "researcher",
        "status" => "paused",
        "name" => "Paused Researcher",
        "slug" => "paused-researcher-agents-live",
        "workspace_root" => Path.join(System.tmp_dir!(), "hydra-x-paused-researcher")
      })

    {:ok, _orphaned_role_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Recover researcher work from an unavailable assignee.",
        "assigned_agent_id" => paused_researcher.id,
        "assigned_role" => "researcher",
        "status" => "planned"
      })

    {:ok, _role_queue_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Queue operator-facing work for the shared researcher role.",
        "assigned_role" => "researcher",
        "status" => "planned",
        "metadata" => %{
          "assignment_mode" => "role_claim",
          "role_queue_dispatch" => %{
            "reason" => "worker_saturated",
            "deferred_until" => "2099-03-18T10:15:00Z"
          }
        }
      })

    {:ok, planner_agent} =
      Runtime.save_agent(%{
        name: "Planner Agent",
        slug: "planner-agent",
        role: "planner",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-planner-agent"),
        description: "planner",
        is_default: false
      })

    {:ok, batch_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Supervise a parallel delegation batch for operator-facing findings.",
        "assigned_agent_id" => planner_agent.id,
        "assigned_role" => "planner",
        "status" => "blocked",
        "execution_mode" => "delegate",
        "priority" => 96,
        "metadata" => %{
          "delegation_batch" => %{
            "mode" => "parallel",
            "expected_count" => 2,
            "roles" => ["researcher", "operator"],
            "items" => [
              %{
                "child_key" => "researcher-memory-export",
                "goal" => "Assess operator-facing memory exports.",
                "assigned_role" => "researcher",
                "status" => "quorum_skipped"
              },
              %{
                "child_key" => "operator-delivery-fallback",
                "goal" => "Prepare the operator delivery fallback note.",
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

    {:ok, _batch_child_two} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Prepare the operator delivery fallback note.",
        "assigned_role" => "operator",
        "status" => "completed",
        "priority" => 94,
        "parent_work_item_id" => batch_parent.id,
        "metadata" => %{"delegation_batch_key" => "operator-delivery-fallback"}
      })

    {:ok, missing_role_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Hold a delegation slot until an operator review is available.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "blocked",
        "execution_mode" => "delegate",
        "priority" => 92,
        "result_refs" => %{
          "follow_up_summary" => %{
            "count" => 2,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan", "review_guided_replan"],
            "entries" => [
              %{
                "work_item_id" => 73_101,
                "type" => "replan",
                "strategy" => "operator_guided_replan",
                "summary" => "Operator-guided recovery",
                "deescalated_from" => "operator_guided_replan",
                "selection_reason" =>
                  "de-escalated from Operator-guided recovery under existing planner recovery pressure (1 existing)",
                "priority_boost" => 3
              },
              %{
                "work_item_id" => 73_102,
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
        "priority" => 91,
        "parent_work_item_id" => missing_role_parent.id,
        "metadata" => %{"delegation_batch_key" => "researcher-context-pass"}
      })

    {:ok, _delivery_brief} =
      Runtime.create_artifact(%{
        "work_item_id" => publish_item.id,
        "type" => "delivery_brief",
        "title" => "Publish-ready summary",
        "summary" => "Prepared operator delivery brief",
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

    {_updated, _record} =
      Runtime.approve_work_item!(extension_item.id, %{
        "requested_action" => "promote_work_item",
        "rationale" => "Recorded for agent review history."
      })

    Runtime.Jobs.record_scheduler_pass(:role_queue_dispatches, %{
      owner: "node:agents-test",
      processed_count: 1,
      required_role_prioritized_count: 1,
      skipped_count: 0,
      error_count: 0,
      results: [
        %{
          agent_id: agent.id,
          agent_name: agent.name,
          role: agent.role,
          work_item_id: publish_item.id,
          status: "completed",
          action: "delivered_publish_summary",
          priority_reason: "required_role",
          priority_urgency: 1
        }
      ]
    })

    Runtime.Jobs.record_scheduler_pass(:assignment_recoveries, %{
      owner: "node:agents-test",
      recovered_count: 1,
      skipped_count: 0,
      error_count: 0,
      results: [
        %{
          assigned_agent_id: agent.id,
          work_item_id: publish_item.id,
          status: "completed",
          action: "researched"
        }
      ]
    })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ "Capability contract"
    assert html =~ "researcher"
    assert html =~ "Recent work items"
    assert html =~ "Awaiting operator"
    assert html =~ "Extensions gated"
    assert html =~ "Map the current operator-facing autonomy work."
    assert html =~ "promoted 1 findings"
    assert html =~ "Decision: Use approved research findings as live operating contex"
    assert html =~ "action promote_work_item"
    assert html =~ "approved_not_enabled"
    assert html =~ "patch_bundle"
    assert html =~ missing_role_parent.goal
    assert html =~ "assigned Research Agent via role capability match"
    assert html =~ "delegation batch 2"
    assert html =~ "strategy ordered"
    assert html =~ "delegation roles researcher, operator"
    assert html =~ "completion quorum 1 met"
    assert html =~ "role quorum operator x1 met"
    assert html =~ "quorum skipped 1"
    assert html =~ "urgent 1"
    assert html =~ "selected-intervention-heavy"
    assert html =~ "dominant operator-guided x1"
    assert html =~ "selected mix operator-guided x1"
    assert html =~ "fallback mix review-guided x1"
    assert html =~ "recovery mix operator-guided x1, review-guided x1"
    assert html =~ "required roles operator x1"
    assert html =~ "pressure h0 m1 l0"
    assert html =~ "repeat deferrals 1 · max 2"
    assert html =~ "deferred 1"
    assert html =~ "expanded 1"
    assert html =~ "last expanded 2099-03-18 10:05:00 UTC"
    assert html =~ "deferred 2 · last deferred 2099-03-18 10:15:00 UTC"
    assert html =~ "supervision budget 2 · active children 1"
    assert html =~ "expansion pressure operator x1 (urgent 0/0, sat 0, avail 1)"
    assert html =~ "expansion severity medium · delay 15s"
    assert html =~ "expansion deferred"
    assert html =~ "cooldown until 2099-03-18 10:25:00 UTC"

    assert html =~ "assignment Research Agent:"
    assert html =~ "exact role match"
    assert html =~ "pressure idle"

    assert html =~ "Role backlog"
    assert html =~ "Queue posture"
    assert html =~ "orphaned role 1"
    assert html =~ "worker pressure open"
    assert html =~ "urgent backlog 0/0"
    assert html =~ "recent role dispatch delivered_publish_summary"
    assert html =~ "required role x1"
    assert html =~ "recent assignment recovery researched"

    assert html =~ "execute_with_review"
    assert html =~ "external_delivery"
  end

  test "agents page shows replan follow-up summaries", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Planner Agent",
        slug: "planner-agent-replan",
        role: "planner",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-planner-agent-replan"),
        description: "planner",
        is_default: false
      })

    {:ok, replan_parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Re-plan the constrained autonomy rollout.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "completed",
        "priority" => 99,
        "result_refs" => %{
          "follow_up_work_item_ids" => [9_101],
          "follow_up_summary" => %{
            "count" => 1,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan"],
            "priority_boosts" => [3],
            "alternative_strategies" => ["narrow_delegate_batch"]
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ replan_parent.goal

    assert html =~
             "replan follow-up queued 1 (Operator-guided recovery; priority +3; alternatives Narrowed delegation batch)"
  end

  test "agents page shows recovery strategy summaries for planner replans", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Recovery Planner",
        slug: "recovery-planner-work-item",
        role: "planner",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-recovery-planner-work-item"),
        description: "planner",
        is_default: false
      })

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
          "recovery_strategy_alternative_summaries" => ["Narrowed delegation batch"],
          "recovery_strategy_pressure_snapshot" => %{
            "base" => "operator_guided_replan",
            "base_selected_count" => 1,
            "base_deescalated_count" => 1,
            "preferred" => "operator_guided_replan",
            "preferred_selected_count" => 1,
            "preferred_deescalated_count" => 2,
            "preferred_fallback_count" => 0,
            "alternative_selected_counts" => %{"narrow_delegate_batch" => 1},
            "alternative_fallback_counts" => %{},
            "alternative_deescalated_counts" => %{"narrow_delegate_batch" => 2}
          },
          "recovery_strategy_selection_reason" =>
            "de-escalated from Operator-guided recovery under existing planner recovery pressure (1 existing)"
        }
      })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ work_item.goal
    assert html =~ "Operator-guided recovery with narrowed delegation fallback"
    assert html =~ "preferred strategy operator-guided"
    assert html =~ "strategy behavior operator review after execution"
    assert html =~ "strategy priority +3"
    assert html =~ "alternative strategies Narrowed delegation batch"
    assert html =~ "pressure base operator-guided s1 d1"
    assert html =~ "preferred operator-guided s1 f0 d2"
    assert html =~ "alternatives"
    assert html =~ "s1 f0 d2"

    assert html =~
             "selection reason de-escalated from Operator-guided recovery under existing planner recovery pressure (1 existing)"
  end

  test "agents page shows queued assignment recoveries with saturation detail", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Recovery Agent",
        slug: "recovery-agent",
        role: "researcher",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-recovery-agent"),
        description: "recovery",
        is_default: false
      })

    Runtime.Jobs.record_scheduler_pass(:assignment_recoveries, %{
      owner: "node:agents-test",
      recovered_count: 1,
      executed_count: 0,
      queued_count: 1,
      skipped_count: 0,
      error_count: 0,
      results: [
        %{
          assigned_agent_id: agent.id,
          work_item_id: 7_777,
          status: "planned",
          action: "reassigned_queued",
          capacity_posture: "saturated",
          queue_reason: "worker_saturated",
          deferred_until: "2026-03-18T10:15:00Z"
        }
      ]
    })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ "recent assignment recovery queued #7777"
    assert html =~ "worker saturated (saturated)"
    assert html =~ "cooldown until 2026-03-18 10:15:00 UTC"
  end

  test "agents page shows saturated role dispatch skips", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Dispatch Agent",
        slug: "dispatch-agent",
        role: "researcher",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-dispatch-agent"),
        description: "dispatch",
        is_default: false
      })

    Runtime.Jobs.record_scheduler_pass(:role_queue_dispatches, %{
      owner: "node:agents-test",
      processed_count: 0,
      pressure_skipped_count: 1,
      skipped_count: 1,
      error_count: 0,
      results: [
        %{
          agent_id: agent.id,
          agent_name: agent.name,
          role: agent.role,
          status: "skipped",
          action: "worker_saturated",
          reason: "worker_saturated",
          capacity_posture: "saturated",
          deferred_until: "2026-03-18T10:15:00Z"
        }
      ]
    })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ "recent role dispatch saturated (saturated)"
    assert html =~ "cooldown until 2026-03-18 10:15:00 UTC"
  end

  test "agents page shows remote-owned role dispatch skips", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Remote Claim Agent",
        slug: "remote-claim-agent",
        role: "researcher",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-remote-claim-agent"),
        description: "remote-claim",
        is_default: false
      })

    Runtime.Jobs.record_scheduler_pass(:role_queue_dispatches, %{
      owner: "node:agents-test",
      processed_count: 0,
      pressure_skipped_count: 0,
      remote_owned_count: 1,
      skipped_count: 1,
      error_count: 0,
      results: [
        %{
          agent_id: agent.id,
          agent_name: agent.name,
          role: agent.role,
          work_item_id: 8_888,
          status: "skipped",
          action: "claimed_remote",
          lease_owner: "node:remote-role-queue",
          lease_expires_at: "2026-03-18T10:20:00Z"
        }
      ]
    })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ "recent role dispatch claimed remotely #8888 by node:remote-role-queue"
    assert html =~ "cooldown until 2026-03-18 10:20:00 UTC"
  end

  test "agents page shows stale claim cleanup results", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Stale Cleanup Agent",
        slug: "stale-cleanup-agent",
        role: "researcher",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-stale-cleanup-agent"),
        description: "stale-cleanup",
        is_default: false
      })

    Runtime.Jobs.record_scheduler_pass(:stale_work_item_claims, %{
      owner: "node:agents-test",
      expired_count: 1,
      skipped_count: 0,
      error_count: 0,
      results: [
        %{
          assigned_agent_id: agent.id,
          work_item_id: 9_999,
          status: "claimed",
          action: "expired_claim"
        }
      ]
    })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ "recent stale cleanup expired_claim #9999"
  end

  test "agents page highlights degraded review queues and degraded publish drafts", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Degraded Agent",
        slug: "degraded-agent",
        role: "researcher",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-degraded-agent"),
        description: "degraded",
        is_default: false
      })

    {:ok, degraded_research} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Review constrained findings before promotion.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "blocked",
        "approval_stage" => "validated",
        "review_required" => true,
        "priority" => 98,
        "result_refs" => %{"degraded" => true, "child_work_item_ids" => [7_601]},
        "metadata" => %{"degraded_execution" => true}
      })

    {:ok, degraded_publish} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Prepare the degraded publish draft for operators.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 97,
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

    {:ok, publish_review} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Approve the degraded publish draft for delivery.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 96,
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

    {:ok, _rejected_publish_review} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Reject the degraded publish draft after review.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "failed",
        "approval_stage" => "validated",
        "priority" => 95,
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
        "goal" => "Queue a publish replan after the degraded delivery was rejected.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated",
        "priority" => 99,
        "result_refs" => %{
          "degraded" => true,
          "follow_up_work_item_ids" => [8_101, 8_102],
          "follow_up_summary" => %{
            "count" => 2,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan"],
            "entries" => [
              %{
                "work_item_id" => 8_101,
                "type" => "replan",
                "strategy" => "operator_guided_replan",
                "summary" => "Operator-guided recovery",
                "deescalated_from" => "operator_guided_replan",
                "selection_reason" =>
                  "de-escalated from Operator-guided recovery under existing planner recovery pressure (1 existing)",
                "alternative_strategies" => ["narrow_delegate_batch"],
                "alternative_summaries" => ["Narrowed delegation batch"],
                "priority_boost" => 3
              },
              %{
                "work_item_id" => 8_102,
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

    {:ok, operator_agent} =
      Runtime.save_agent(%{
        name: "Intervention Operator",
        slug: "intervention-operator",
        role: "operator",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-intervention-operator"),
        description: "operator",
        is_default: false
      })

    {:ok, _operator_follow_up} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Route the rejected delegation strategy through operator intervention.",
        "assigned_agent_id" => operator_agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "priority" => 100,
        "metadata" => %{
          "task_type" => "delegation_pressure_operator_follow_up",
          "reason" => "role_capacity_constrained",
          "constraint_strategy" =>
            "Reduce parallel fan-out, wait for healthier worker capacity, and re-plan the next delegation step around the constrained role.",
          "assignment_mode" => "role_claim"
        }
      })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ degraded_research.goal
    assert html =~ "degraded review queued 1"
    assert html =~ degraded_publish.goal
    assert html =~ "delivery degraded draft telegram"
    assert html =~ publish_review.goal
    assert html =~ "Approve degraded delivery"
    assert html =~ "degraded delivery awaiting approval telegram"
    assert html =~ "recovery switch slack"
    assert html =~ "explicit-signal"
    assert html =~ "delivery internal"

    assert html =~ "replan queued 2"
    assert html =~ "Operator-guided recovery"
    assert html =~ "priority +3"
    assert html =~ "active 2"
    assert html =~ "+1 more: Reviewer-guided recovery"

    assert html =~ "operator intervention prepared role_capacity_constrained"

    assert html =~
             "constraint strategy Reduce parallel fan-out, wait for healthier worker capacity, and re-plan the next delegation step around the constrained role."
  end

  test "agents page can approve a merge-ready work item from the control plane", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Builder Agent",
        slug: "builder-agent",
        role: "builder",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-builder-agent"),
        description: "builder",
        is_default: false
      })

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "engineering",
        "goal" => "Promote this work item from the agents page.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element("#approve-work-item-#{work_item.id}")
    |> render_click()

    html = render(view)
    assert html =~ "Approved engineering work item ##{work_item.id}"
    assert Runtime.get_work_item!(work_item.id).approval_stage == "merge_ready"
  end

  test "agents page can repair a workspace scaffold", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Repair Agent",
        slug: "repair-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-repair-agent"),
        description: "repair",
        is_default: false
      })

    soul_path = Path.join(agent.workspace_root, "SOUL.md")
    File.rm_rf!(soul_path)

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="repair_workspace"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Workspace template repaired"
    assert File.exists?(soul_path)
  end

  test "agents page can start and stop runtime", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Runtime Agent",
        slug: "runtime-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-runtime-agent"),
        description: "runtime",
        is_default: false,
        status: "paused"
      })

    {:ok, view, _html} = live(conn, ~p"/agents")
    assert render(view) =~ "runtime down"

    view
    |> element(~s(button[phx-click="start_runtime"][phx-value-id="#{agent.id}"]))
    |> render_click()

    assert Runtime.agent_runtime_status(agent.id).running

    view
    |> element(~s(button[phx-click="stop_runtime"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agent runtime stopped"
    assert html =~ "runtime down"
    refute Runtime.agent_runtime_status(agent.id).running
  end

  test "agents page can refresh a bulletin from memory", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Bulletin Agent",
        slug: "bulletin-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-bulletin-agent"),
        description: "bulletin",
        is_default: false
      })

    {:ok, _memory} =
      HydraX.Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Operators can inspect the current bulletin.",
        importance: 0.9,
        metadata: %{
          "source_file" => "ops/agents.md",
          "source_channel" => "webchat"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="refresh_bulletin"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agent bulletin refreshed"
    assert html =~ "Operators can inspect the current bulletin."
    assert html =~ "Top bulletin memories"
    assert html =~ "channel webchat"
    assert html =~ "file ops/agents.md"
  end

  test "agents page can update a compaction policy", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Compaction Agent",
        slug: "compaction-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-compaction-agent"),
        description: "compaction",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> form("#compaction-policy-#{agent.id}", %{
      "compaction_policy" => %{
        "agent_id" => to_string(agent.id),
        "soft" => "5",
        "medium" => "9",
        "hard" => "13"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Compaction policy updated"
    assert html =~ "Soft 5"
    assert Runtime.compaction_policy(agent.id) == %{soft: 5, medium: 9, hard: 13}
  end

  test "agents page can save and reset an agent-specific tool policy override", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Tool Policy Agent",
        slug: "tool-policy-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-tool-policy-agent"),
        description: "tool policy",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> form("#agent-tool-policy-#{agent.id}", %{
      "agent_tool_policy" => %{
        "agent_id" => to_string(agent.id),
        "workspace_list_enabled" => "true",
        "workspace_read_enabled" => "true",
        "workspace_write_enabled" => "true",
        "http_fetch_enabled" => "true",
        "browser_automation_enabled" => "true",
        "web_search_enabled" => "false",
        "shell_command_enabled" => "false",
        "shell_allowlist_csv" => "pwd,ls",
        "http_allowlist_csv" => "example.com",
        "workspace_write_channels_csv" => "cli,control_plane",
        "http_fetch_channels_csv" => "cli,scheduler",
        "browser_automation_channels_csv" => "cli",
        "web_search_channels_csv" => "cli",
        "shell_command_channels_csv" => "cli"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Agent tool policy updated"
    assert html =~ "override active"

    policy = Runtime.effective_tool_policy(agent.id)
    assert policy.workspace_write_enabled
    assert policy.browser_automation_enabled
    refute policy.web_search_enabled
    refute policy.shell_command_enabled
    assert policy.http_allowlist == ["example.com"]
    assert policy.workspace_write_channels == ["cli", "control_plane"]
    assert policy.browser_automation_channels == ["cli"]
    assert policy.shell_command_channels == ["cli"]

    view
    |> element(~s(button[phx-click="reset_agent_tool_policy"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agent tool policy override removed"
    assert html =~ "inherits global"
    refute Runtime.get_agent_tool_policy(agent.id)
  end

  test "agents page can save and reset an agent-specific control policy override", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Control Policy Agent",
        slug: "control-policy-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-control-policy-agent"),
        description: "control policy",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> form("#agent-control-policy-#{agent.id}", %{
      "agent_control_policy" => %{
        "agent_id" => to_string(agent.id),
        "require_recent_auth_for_sensitive_actions" => "true",
        "recent_auth_window_minutes" => "4",
        "interactive_delivery_channels_csv" => "webchat",
        "job_delivery_channels_csv" => "discord,slack",
        "ingest_roots_csv" => "ingest,docs"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Agent control policy updated"
    assert html =~ "override active"

    policy = Runtime.effective_control_policy(agent.id)
    assert policy.recent_auth_window_minutes == 4
    assert policy.interactive_delivery_channels == ["webchat"]
    assert policy.job_delivery_channels == ["discord", "slack"]
    assert policy.ingest_roots == ["ingest", "docs"]

    view
    |> element(~s(button[phx-click="reset_agent_control_policy"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agent control policy override removed"
    assert html =~ "inherits global"
    refute Runtime.get_agent_control_policy(agent.id)
  end

  test "agents page shows the consolidated effective policy view", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Effective Policy Agent",
        slug: "effective-policy-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-effective-policy-agent"),
        description: "effective policy",
        is_default: false
      })

    {:ok, _tool_policy} =
      Runtime.save_agent_tool_policy(agent.id, %{
        browser_automation_enabled: true,
        browser_automation_channels_csv: "cli"
      })

    {:ok, _control_policy} =
      Runtime.save_agent_control_policy(agent.id, %{
        interactive_delivery_channels_csv: "webchat",
        job_delivery_channels_csv: "discord,slack",
        ingest_roots_csv: "ingest,docs"
      })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ "Effective policy"
    assert html =~ "interactive webchat"
    assert html =~ "jobs discord, slack"
    assert html =~ "ingest ingest, docs"
    assert html =~ "browser_automation on (cli)"
  end

  test "agents page can save and warm provider routing", %{conn: conn} do
    previous = Application.get_env(:hydra_x, :provider_test_request_fn)

    Application.put_env(:hydra_x, :provider_test_request_fn, fn _opts ->
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
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :provider_test_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :provider_test_request_fn)
      end
    end)

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Agent Route Provider",
        kind: "openai_compatible",
        base_url: "https://agent-route.test",
        api_key: "secret",
        model: "gpt-agent-route",
        enabled: false
      })

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Routing Agent",
        slug: "routing-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-routing-agent"),
        description: "routing",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> form("#provider-routing-#{agent.id}", %{
      "provider_routing" => %{
        "agent_id" => to_string(agent.id),
        "default_provider_id" => to_string(provider.id),
        "fallback_provider_ids_csv" => "",
        "channel_provider_id" => "",
        "scheduler_provider_id" => "",
        "cortex_provider_id" => "",
        "compactor_provider_id" => ""
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Agent provider routing updated"
    assert html =~ "Agent Route Provider"

    view
    |> element(~s(button[phx-click="warm_provider_route"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Provider warmup ready via Agent Route Provider"
    assert html =~ "warmup ready"
    assert Runtime.agent_runtime_status(agent.id).warmup_status == "ready"
  end

  test "agents page can discover and toggle workspace skills", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Skills Agent",
        slug: "skills-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-skills-agent"),
        description: "skills",
        is_default: false
      })

    skill_dir = Path.join([agent.workspace_root, "skills", "deploy-checks"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Deploy Checks\nsummary: Run deployment verification steps for staged rollouts.\nversion: 1.2.0\ntags: deploy,release,checks\ntools: shell_command,web_search\nchannels: cli,slack\nrequires: release-window\n---\n# Deploy Checks\n\nRun deployment verification steps for staged rollouts."
    )

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="refresh_skills"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Discovered 1 skills"
    assert html =~ "Deploy Checks"
    assert html =~ "tags: deploy, release, checks"
    assert html =~ "tools: shell_command, web_search"
    assert html =~ "channels: cli, slack"
    assert html =~ "requires: release-window"
    assert html =~ "1.2.0"
    assert html =~ "enabled"
    assert html =~ "manifest valid"

    [skill] = Runtime.list_skills(agent_id: agent.id)
    assert get_in(skill.metadata, ["tags"]) == ["deploy", "release", "checks"]
    assert get_in(skill.metadata, ["tools"]) == ["shell_command", "web_search"]
    assert get_in(skill.metadata, ["channels"]) == ["cli", "slack"]
    assert get_in(skill.metadata, ["requires"]) == ["release-window"]
    assert get_in(skill.metadata, ["version"]) == "1.2.0"
    assert get_in(skill.metadata, ["manifest_valid"]) == true

    view
    |> element(~s(button[phx-click="toggle_skill"][phx-value-id="#{skill.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Skill disabled"
    assert html =~ "disabled"
    refute Runtime.get_skill!(skill.id).enabled
  end

  test "agents page surfaces invalid skill manifests", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Invalid Skills Agent",
        slug: "invalid-skills-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-invalid-skills-agent"),
        description: "invalid skills",
        is_default: false
      })

    skill_dir = Path.join([agent.workspace_root, "skills", "broken-skill"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Broken Skill\nsummary: Invalid metadata.\ntools: unknown_tool\nchannels: cli,unknown_channel\nrequires: env:\n---\n# Broken Skill\n\nThis should be flagged."
    )

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="refresh_skills"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Broken Skill"
    assert html =~ "manifest invalid"
    assert html =~ "validation: unknown tool unknown_tool"
    assert html =~ "unknown channel unknown_channel"
    assert html =~ "malformed requirement env:"
  end

  test "agents page can discover and toggle agent MCP integrations", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "MCP Agent",
        slug: "mcp-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-mcp-agent"),
        description: "mcp",
        is_default: false
      })

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

    assert {:ok, _server} =
             Runtime.save_mcp_server(%{
               name: "Docs MCP",
               transport: "http",
               url: "https://mcp.example.test",
               enabled: true
             })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert {:ok, _results} = Runtime.list_agent_mcp_actions(agent.id)

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="refresh_mcp"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Discovered 1 MCP integrations"
    assert html =~ "Docs MCP"
    assert html =~ "2 actions"
    assert html =~ "enabled"

    [binding] = Runtime.list_agent_mcp_servers(agent.id)

    assert get_in(binding.mcp_server_config.metadata || %{}, ["actions"]) == [
             "search_docs",
             "get_status"
           ]

    view
    |> element(~s(button[phx-click="toggle_agent_mcp"][phx-value-id="#{binding.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "MCP integration disabled"
    assert html =~ "disabled"
    refute Runtime.get_agent_mcp_server!(binding.id).enabled
  end
end
