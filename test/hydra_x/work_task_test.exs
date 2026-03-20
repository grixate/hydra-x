defmodule HydraX.WorkTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "work task can show and approve a work item" do
    agent = Runtime.ensure_default_agent!()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "engineering",
        "goal" => "Promote the runtime work item from the CLI.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated",
        "result_refs" => %{
          "follow_up_summary" => %{
            "count" => 1,
            "types" => ["replan"],
            "strategies" => ["operator_guided_replan"],
            "summaries" => ["Operator-guided recovery"]
          }
        }
      })

    {:ok, _artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "code_change_set",
        "title" => "Runtime patch",
        "summary" => "Prepared runtime patch"
      })

    {:ok, _review_artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "review_report",
        "title" => "Delivery review",
        "summary" => "Compared publish options",
        "payload" => %{
          "delivery_decision_context" => [
            %{
              "content" =>
                "Route the revised publish through Slack because the operator rejected Telegram delivery."
            }
          ],
          "delivery_decision_snapshot" => %{
            "prior_summary" => "Keep the original Telegram path until the summary is revised.",
            "comparison_summary" =>
              "Shifted delivery guidance from the prior path to the current recommendation."
          }
        }
      })

    {:ok, _synthesis_artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "decision_ledger",
        "title" => "Planner synthesis",
        "summary" => "Carried delivery decisions forward",
        "payload" => %{
          "decision_type" => "delegation_synthesis",
          "delivery_decisions" => [
            %{
              "content" =>
                "Keep the rerouted Slack path because it preserves operator intent while staying publish-ready."
            }
          ],
          "delivery_decision_snapshot" => %{
            "prior_summary" => "Keep the original Telegram path until the summary is revised.",
            "comparison_summary" =>
              "Shifted delivery guidance from the prior path to the current recommendation."
          }
        }
      })

    {:ok, _publish_artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "delivery_brief",
        "title" => "Publish brief",
        "summary" => "Prepared rerouted publish brief",
        "payload" => %{
          "delivery_decision_snapshot" => %{
            "decision_scope" => "publish",
            "current_summary" =>
              "Selected slack -> ops-room using rerouted delivery guidance at confidence 0.74.",
            "prior_summary" => "Previous delivery path: telegram -> ops-room",
            "comparison_summary" =>
              "Shifted delivery guidance from the prior path to the current recommendation."
          }
        }
      })

    Mix.Task.reenable("hydra_x.work")

    show_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run(["show", to_string(work_item.id)])
      end)

    assert show_output =~ "work_item=#{work_item.id}"
    assert show_output =~ "kind=engineering"
    assert show_output =~ "follow_up_count=1"
    assert show_output =~ "follow_up_types=replan"
    assert show_output =~ "follow_up_strategies=operator_guided_replan"
    assert show_output =~ "follow_up_summaries=Operator-guided recovery"

    assert show_output =~
             "follow_up_detail\t#{work_item.id}\trecovery_summary_1\tOperator-guided recovery"

    assert show_output =~ "artifact\tcode_change_set"
    assert show_output =~ "artifact_detail"
    assert show_output =~ "review_delivery_decision_1"
    assert show_output =~ "Route the revised publish through Slack"
    assert show_output =~ "synthesis_delivery_decision_1"
    assert show_output =~ "Keep the rerouted Slack path"
    assert show_output =~ "publish_delivery_decision_1"
    assert show_output =~ "Selected slack -> ops-room using rerouted delivery guidance"
    assert show_output =~ "decision_comparison"

    Mix.Task.reenable("hydra_x.work")

    approve_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run([
          "approve",
          to_string(work_item.id),
          "--action",
          "merge_ready",
          "--reason",
          "CLI promotion complete."
        ])
      end)

    assert approve_output =~ "approval_stage=merge_ready"
    assert approve_output =~ "decision=approved"
    assert approve_output =~ "action=merge_ready"

    Mix.Task.reenable("hydra_x.work")

    artifact_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run(["show", to_string(work_item.id)])
      end)

    assert artifact_output =~ "artifact_approval"
    assert artifact_output =~ "merge_ready"
  end

  test "work task can reject a work item" do
    agent = Runtime.ensure_default_agent!()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "extension",
        "goal" => "Reject the extension rollout from the CLI.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    Mix.Task.reenable("hydra_x.work")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run([
          "reject",
          to_string(work_item.id),
          "--action",
          "enable_extension",
          "--reason",
          "CLI rejected the extension rollout."
        ])
      end)

    assert output =~ "status=failed"
    assert output =~ "decision=rejected"
    assert output =~ "action=enable_extension"
  end

  test "work task can inspect and approve an artifact directly" do
    agent = Runtime.ensure_default_agent!()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "engineering",
        "goal" => "Approve an artifact directly from the CLI.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {:ok, artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "review_report",
        "title" => "Runtime proposal",
        "summary" => "Prepared runtime proposal",
        "payload" => %{
          "delivery_decision_context" => [
            %{
              "content" =>
                "Hold the publish brief on the control plane until the reviewer approves external delivery."
            }
          ],
          "delivery_decision_snapshot" => %{
            "prior_summary" => "External publication is still blocked.",
            "comparison_summary" => "Retained the prior delivery guidance."
          }
        }
      })

    Mix.Task.reenable("hydra_x.work")

    approve_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run([
          "approve-artifact",
          to_string(artifact.id),
          "--action",
          "publish_review_report",
          "--reason",
          "CLI approved artifact publication."
        ])
      end)

    assert approve_output =~ "artifact=#{artifact.id}"
    assert approve_output =~ "review_status=approved"

    Mix.Task.reenable("hydra_x.work")

    show_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run(["show-artifact", to_string(artifact.id)])
      end)

    assert show_output =~ "approvals=1"
    assert show_output =~ "publish_review_report"
    assert show_output =~ "review_delivery_decision_1"
    assert show_output =~ "Hold the publish brief on the control plane"
    assert show_output =~ "decision_comparison"
  end

  test "work task list shows recovery summaries" do
    agent = Runtime.ensure_default_agent!()

    {:ok, guided_item} =
      Runtime.save_work_item(%{
        "kind" => "plan",
        "goal" => "Recover a constrained planner branch.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "planned",
        "approval_stage" => "proposal_only",
        "metadata" => %{
          "recovery_strategy_summary" => "Operator-guided recovery"
        }
      })

    {:ok, follow_up_item} =
      Runtime.save_work_item(%{
        "kind" => "plan",
        "goal" => "Finalize the parent planner tree.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "blocked",
        "approval_stage" => "validated",
        "result_refs" => %{
          "follow_up_summary" => %{
            "count" => 1,
            "types" => ["replan"],
            "strategies" => ["review_guided_replan"],
            "summaries" => ["Reviewer-guided recovery"]
          }
        }
      })

    Mix.Task.reenable("hydra_x.work")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run(["--limit", "10"])
      end)

    assert output =~
             "#{guided_item.id}\tplan\tplanned\tplanner\tproposal_only\tRecover a constrained planner branch.\tOperator-guided recovery"

    assert output =~
             "#{follow_up_item.id}\tplan\tblocked\tplanner\tvalidated\tFinalize the parent planner tree.\tReviewer-guided recovery"
  end
end
