defmodule HydraX.MCPTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  setup do
    previous = Application.get_env(:hydra_x, :mcp_http_request_fn)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    :ok
  end

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

  test "mcp task can invoke an enabled HTTP binding with json and param overrides" do
    agent = create_agent()

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      assert opts[:url] == "https://mcp.example.test/invoke"
      assert opts[:json][:action] == "search_docs"
      assert opts[:json][:params] == %{"limit" => 5, "query" => "hydra"}

      {:ok, %{status: 200, body: %{"results" => [%{"title" => "Hydra Docs"}]}}}
    end)

    assert {:ok, _server} =
             Runtime.save_mcp_server(%{
               name: "Docs HTTP MCP",
               transport: "http",
               url: "https://mcp.example.test",
               enabled: true
             })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)

    Mix.Task.reenable("hydra_x.mcp")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Mcp.run([
          "invoke",
          agent.slug,
          "search_docs",
          "--server",
          "Docs",
          "--json",
          ~s({"limit":2}),
          "--param",
          "query=hydra",
          "--param",
          "limit=5"
        ])
      end)

    assert output =~ "agent=#{agent.slug}"
    assert output =~ "action=search_docs"
    assert output =~ "count=1"
    assert output =~ "Docs HTTP MCP"
    assert output =~ "ok"
    assert output =~ "HTTP 200 https://mcp.example.test/invoke"
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
