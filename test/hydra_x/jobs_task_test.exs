defmodule HydraX.JobsTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "jobs task can filter jobs by kind and state" do
    Mix.Task.reenable("hydra_x.jobs")
    agent = Runtime.ensure_default_agent!()

    {:ok, _prompt_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Filtered Prompt Job",
        kind: "prompt",
        interval_minutes: 30,
        enabled: true
      })

    {:ok, _paused_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Paused Backup Job",
        kind: "backup",
        interval_minutes: 120,
        enabled: false
      })

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run([
          "--kind",
          "prompt",
          "--enabled",
          "true",
          "--search",
          "Filtered"
        ])
      end)

    assert output =~ "Filtered Prompt Job\tprompt\tenabled"
    refute output =~ "Paused Backup Job"
  end
end
