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

    {:ok, publish_parent} =
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
        "title" => "Publish-ready summary",
        "summary" => "Prepared operator delivery brief",
        "payload" => %{
          "publish_objective" =>
            "Revise the summary and route it through telegram for ops-room publication.",
          "destination_rationale" =>
            "Selected telegram -> ops-room using current publish policy at confidence 0.78 with ready posture.",
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
    assert html =~ publish_parent.goal
    assert html =~ "publish follow-up queued 1"
    assert html =~ "delivery delivered telegram"
    assert html =~ "ops-room"

    assert html =~
             "objective Revise the summary and route it through telegram for ops-room publication."

    assert html =~
             "prior decision Keep the previous publish path on the control plane until the summary is revised."

    assert html =~
             "review decision Route the revised summary through Slack because the operator requested a channel switch."

    assert html =~
             "synthesis decision Keep the rerouted Slack plan because it preserves operator intent without reopening Telegram delivery."

    assert html =~
             "rationale Selected telegram"

    assert html =~ "confidence 0.78 (ready)"
    assert html =~ "current publish policy"

    assert html =~
             "guidance Confirm the operator-ready summary with the on-call owner before publication."

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
          "follow_up_summary" => %{"count" => 1, "types" => ["replan"]}
        }
      })

    {:ok, _view, html} = live(conn, ~p"/agents")

    assert html =~ replan_parent.goal
    assert html =~ "replan follow-up queued 1"
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
          "follow_up_work_item_ids" => [8_101],
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
    assert html =~ "replan queued 1"
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
