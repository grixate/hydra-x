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

    assert output =~ "Filtered Prompt Job\tprompt\tevery-30m\tenabled"
    refute output =~ "Paused Backup Job"
  end

  test "jobs task lists weekly schedules with a human-readable summary" do
    Mix.Task.reenable("hydra_x.jobs")
    agent = Runtime.ensure_default_agent!()

    {:ok, _job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Weekly Planning",
        kind: "prompt",
        schedule_mode: "weekly",
        weekday_csv: "mon,fri",
        run_hour: 8,
        run_minute: 15,
        enabled: true
      })

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run(["--search", "Weekly Planning"])
      end)

    assert output =~ "Weekly Planning\tprompt\tmon,fri@08:15\tenabled"
  end

  test "jobs task can delete jobs" do
    Mix.Task.reenable("hydra_x.jobs")
    agent = Runtime.ensure_default_agent!()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Disposable Job",
        kind: "prompt",
        interval_minutes: 15,
        enabled: true
      })

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run(["delete", to_string(job.id)])
      end)

    assert output =~ "deleted_job=#{job.id}"
    assert_raise Ecto.NoResultsError, fn -> Runtime.get_scheduled_job!(job.id) end
  end
end
