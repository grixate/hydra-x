defmodule HydraX.MCPTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "mcp task can refresh and list agent bindings" do
    agent = create_agent()

    assert {:ok, _server} =
             Runtime.save_mcp_server(%{
               name: "CLI MCP",
               transport: "stdio",
               command: "cat",
               enabled: true
             })

    Mix.Task.reenable("hydra_x.mcp")

    refresh_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Mcp.run(["refresh-bindings", agent.slug])
      end)

    assert refresh_output =~ "agent=#{agent.slug}"
    assert refresh_output =~ "refreshed=1"
    assert refresh_output =~ "CLI MCP"

    Mix.Task.reenable("hydra_x.mcp")

    bindings_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Mcp.run(["bindings", agent.slug])
      end)

    assert bindings_output =~ "CLI MCP"
    assert bindings_output =~ "enabled"
    assert bindings_output =~ "ok"
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "MCP CLI Agent #{unique}",
        slug: "mcp-cli-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-mcp-cli-#{unique}"),
        description: "mcp cli test agent",
        is_default: false
      })

    agent
  end
end
