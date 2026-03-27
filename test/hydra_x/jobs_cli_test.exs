defmodule HydraX.JobsCliTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "jobs task can filter and export runs" do
    agent = create_agent()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "CLI Export Job",
        kind: "backup",
        interval_minutes: 10,
        enabled: true
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"

    Mix.Task.reenable("hydra_x.jobs")

    runs_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run([
          "runs",
          "--status",
          "success",
          "--kind",
          "backup",
          "--search",
          "CLI Export"
        ])
      end)

    assert runs_output =~ "CLI Export Job"
    assert runs_output =~ "status=success"

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-jobs-cli-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    Mix.Task.reenable("hydra_x.jobs")

    export_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run([
          "export-runs",
          "--status",
          "success",
          "--kind",
          "backup",
          "--output",
          output_root
        ])
      end)

    assert export_output =~ "markdown="
    assert export_output =~ "json="
    assert export_output =~ "count=1"
  end

  test "jobs task saves retention policy on create" do
    agent = create_agent()

    Mix.Task.reenable("hydra_x.jobs")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run([
          "create",
          "--agent",
          agent.slug,
          "--name",
          "CLI Retention Job",
          "--kind",
          "prompt",
          "--interval-minutes",
          "15",
          "--run-retention-days",
          "5"
        ])
      end)

    assert output =~ "job="

    [job | _] =
      Runtime.list_hx_scheduled_jobs(limit: 20)
      |> Enum.filter(&(&1.name == "CLI Retention Job"))

    assert job.run_retention_days == 5
  end

  test "jobs task supports natural schedule text on create" do
    agent = create_agent()

    Mix.Task.reenable("hydra_x.jobs")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Jobs.run([
          "create",
          "--agent",
          agent.slug,
          "--name",
          "CLI Natural Schedule Job",
          "--kind",
          "prompt",
          "--schedule",
          "weekly tue,thu 07:45"
        ])
      end)

    assert output =~ "job="
    assert output =~ "weekly tue,thu 07:45"

    [job | _] =
      Runtime.list_hx_scheduled_jobs(limit: 20)
      |> Enum.filter(&(&1.name == "CLI Natural Schedule Job"))

    assert job.schedule_mode == "weekly"
    assert job.weekday_csv == "tue,thu"
    assert job.run_hour == 7
    assert job.run_minute == 45
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Jobs CLI Agent #{unique}",
        slug: "jobs-cli-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-jobs-cli-#{unique}"),
        description: "jobs cli test agent",
        is_default: false
      })

    agent
  end
end
