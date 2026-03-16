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
        "approval_stage" => "validated"
      })

    {:ok, _artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "code_change_set",
        "title" => "Runtime patch",
        "summary" => "Prepared runtime patch"
      })

    Mix.Task.reenable("hydra_x.work")

    show_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Work.run(["show", to_string(work_item.id)])
      end)

    assert show_output =~ "work_item=#{work_item.id}"
    assert show_output =~ "kind=engineering"
    assert show_output =~ "artifact\tcode_change_set"

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
end
