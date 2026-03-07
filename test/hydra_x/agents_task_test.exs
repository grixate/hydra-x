defmodule HydraX.AgentsTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "agents task can set the default agent and repair its workspace" do
    Mix.Task.reenable("hydra_x.agents")
    agent = create_agent()
    soul_path = Path.join(agent.workspace_root, "SOUL.md")
    File.rm_rf!(soul_path)

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Agents.run(["default", to_string(agent.id)])
        Mix.Task.reenable("hydra_x.agents")
        Mix.Tasks.HydraX.Agents.run(["repair", to_string(agent.id)])
      end)

    assert output =~ "default=#{agent.slug}"
    assert output =~ "workspace=#{agent.workspace_root}"
    assert Runtime.get_default_agent().id == agent.id
    assert File.exists?(soul_path)
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Agent Task #{unique}",
        slug: "agent-task-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-agent-task-#{unique}"),
        description: "agent task test",
        is_default: false
      })

    agent
  end
end
