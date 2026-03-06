defmodule HydraX.Tools.ToolSafetyTest do
  use HydraX.DataCase

  alias HydraX.Runtime
  alias HydraX.Tools.{HttpFetch, ShellCommand, WorkspaceRead}

  test "workspace reads stay inside the agent workspace" do
    agent = create_agent()
    soul_path = Path.join(agent.workspace_root, "SOUL.md")
    File.write!(soul_path, "Hydra soul")

    assert {:ok, result} =
             WorkspaceRead.execute(%{path: "SOUL.md"}, %{workspace_root: agent.workspace_root})

    assert result.path == "SOUL.md"
    assert result.excerpt =~ "Hydra soul"

    assert {:error, :path_outside_workspace} =
             WorkspaceRead.execute(%{path: "../secrets.txt"}, %{
               workspace_root: agent.workspace_root
             })
  end

  test "http fetch blocks localhost style targets before issuing a request" do
    request_fn = fn _opts ->
      send(self(), :request_attempted)
      {:ok, %{status: 200, body: "should not happen", headers: []}}
    end

    assert {:error, :blocked_host} =
             HttpFetch.execute(%{url: "http://localhost:4000/health"}, %{request_fn: request_fn})

    refute_received :request_attempted
  end

  test "http fetch enforces an optional host allowlist" do
    previous = System.get_env("HYDRA_X_HTTP_ALLOWLIST")
    System.put_env("HYDRA_X_HTTP_ALLOWLIST", "example.com")

    on_exit(fn ->
      if previous do
        System.put_env("HYDRA_X_HTTP_ALLOWLIST", previous)
      else
        System.delete_env("HYDRA_X_HTTP_ALLOWLIST")
      end
    end)

    request_fn = fn _opts ->
      send(self(), :request_attempted)
      {:ok, %{status: 200, body: "should not happen", headers: []}}
    end

    assert {:error, :host_not_allowlisted} =
             HttpFetch.execute(%{url: "https://not-example.test/data"}, %{request_fn: request_fn})

    refute_received :request_attempted
  end

  test "shell commands run inside the workspace when allowlisted" do
    agent = create_agent()

    assert {:ok, result} =
             ShellCommand.execute(%{command: "pwd"}, %{workspace_root: agent.workspace_root})

    assert result.command == "pwd"
    assert result.output =~ agent.workspace_root
  end

  test "shell commands block disallowed git subcommands" do
    agent = create_agent()

    assert {:error, :git_subcommand_not_allowed} =
             ShellCommand.execute(
               %{command: "git checkout -b nope"},
               %{workspace_root: agent.workspace_root}
             )
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Tool Agent #{unique}",
        slug: "tool-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-tools-#{unique}"),
        description: "tool test agent",
        is_default: false
      })

    agent
  end
end
