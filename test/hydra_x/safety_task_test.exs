defmodule HydraX.SafetyTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime
  alias HydraX.Safety

  test "safety task lists filtered events" do
    Mix.Task.reenable("hydra_x.safety")
    agent = create_agent()

    assert {:ok, _warn} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "tool",
               level: "warn",
               message: "blocked shell command"
             })

    assert {:ok, _error} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "gateway",
               level: "error",
               message: "delivery failed"
             })

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Safety.run(["--level", "error", "--limit", "10"])
      end)

    assert output =~ "gateway"
    assert output =~ "delivery failed"
    refute output =~ "blocked shell command"
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Safety Task Agent #{unique}",
        slug: "safety-task-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-safety-#{unique}"),
        description: "safety task test agent",
        is_default: false
      })

    HydraX.Budget.ensure_policy!(agent.id)
    agent
  end
end
