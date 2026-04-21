defmodule HydraX.Product.WorkspaceDockerTest do
  @moduledoc """
  Tests for the Docker backend without requiring a real docker daemon.
  The `:docker_runner` application env is overridden with a configurable
  fake that returns canned `{output, exit_code}` tuples.
  """

  use HydraX.DataCase, async: false

  alias HydraX.Product.Project
  alias HydraX.Product.Workspace
  alias HydraX.Product.Workspace.Backend.Docker
  alias HydraX.Product.WorkspaceEvents
  alias HydraX.Product.Workspaces
  alias HydraX.Repo
  alias HydraX.Runtime.AgentProfile

  setup do
    suffix = System.unique_integer([:positive])

    tmp_root = Path.join(System.tmp_dir!(), "hx_docker_test_#{suffix}")
    File.mkdir_p!(tmp_root)
    prev_root = Application.get_env(:hydra_x, :workspace_root)
    Application.put_env(:hydra_x, :workspace_root, tmp_root)

    # Test runner: uses the test process dictionary so each test can
    # configure its own canned responses keyed by docker subcommand.
    test_pid = self()

    runner = fn args, _opts ->
      send(test_pid, {:docker_call, args})

      case args do
        ["docker", "run" | _] -> {"fake-container-#{suffix}\n", 0}
        ["docker", "inspect" | _] -> {"true\n", 0}
        ["docker", "exec", _container, "echo" | rest] -> {Enum.join(rest, " ") <> "\n", 0}
        # `cat /nonexistent` → simulate non-zero exit
        ["docker", "exec", _container, "cat", "/nonexistent" | _] ->
          {"cat: /nonexistent: No such file\n", 1}

        # `cat /also/missing` → simulate exit 2
        ["docker", "exec", _container, "cat", "/also/missing" | _] -> {"err\n", 2}
        ["docker", "exec", _container, _ | _] -> {"", 0}
        ["docker", "rm" | _] -> {"", 0}
        _ -> {"", 0}
      end
    end

    prev_runner = Application.get_env(:hydra_x, :docker_runner)
    Application.put_env(:hydra_x, :docker_runner, runner)

    on_exit(fn ->
      Application.put_env(:hydra_x, :workspace_root, prev_root)

      if prev_runner do
        Application.put_env(:hydra_x, :docker_runner, prev_runner)
      else
        Application.delete_env(:hydra_x, :docker_runner)
      end

      File.rm_rf!(tmp_root)
    end)

    project = insert_minimal_project!(suffix)
    {:ok, project: project, suffix: suffix, tmp_root: tmp_root}
  end

  defp insert_minimal_project!(suffix) do
    researcher = insert_agent!("docker-researcher-#{suffix}")
    strategist = insert_agent!("docker-strategist-#{suffix}")

    %Project{}
    |> Project.changeset(%{
      "name" => "Docker WS #{suffix}",
      "slug" => "docker-ws-#{suffix}",
      "researcher_agent_id" => researcher.id,
      "strategist_agent_id" => strategist.id
    })
    |> Repo.insert!()
  end

  defp insert_agent!(slug) do
    %AgentProfile{}
    |> AgentProfile.changeset(%{
      "name" => slug,
      "slug" => slug,
      "workspace_root" => Path.join(System.tmp_dir!(), "hx_agent_#{slug}")
    })
    |> Repo.insert!()
  end

  describe "provisioning a docker workspace" do
    test "starts a container and stores its id", %{project: project} do
      {:ok, ws} = Workspaces.provision(project, sandbox_mode: "docker")
      assert ws.sandbox_mode == "docker"
      assert is_binary(ws.container_id)
      assert String.starts_with?(ws.container_id, "fake-container-")

      assert_received {:docker_call, ["docker", "run" | _]}
    end

    test "is idempotent — re-provisioning checks the existing container", %{project: project} do
      {:ok, ws1} = Workspaces.provision(project, sandbox_mode: "docker")
      {:ok, ws2} = Workspaces.provision(project, sandbox_mode: "docker")
      assert ws2.id == ws1.id
      assert_received {:docker_call, ["docker", "inspect" | _]}
    end
  end

  describe "exec inside the container" do
    setup %{project: project} do
      {:ok, ws} = Workspaces.provision(project, sandbox_mode: "docker")
      {:ok, workspace: ws}
    end

    test "returns stdout and exit code on success", %{workspace: ws} do
      assert {:ok, %{exit_code: 0, stdout: out}} =
               Docker.exec(ws, ["echo", "hello"], [])

      assert String.trim(out) == "hello"
    end

    test "returns non-zero exit code without raising", %{workspace: ws} do
      assert {:ok, %{exit_code: 1}} = Docker.exec(ws, ["cat", "/nonexistent"], [])
      assert {:ok, %{exit_code: 2}} = Docker.exec(ws, ["cat", "/also/missing"], [])
    end

    test "rejects programs not in the host allowlist", %{workspace: ws} do
      assert {:error, {:command_not_allowed, "curl"}} = Docker.exec(ws, ["curl"], [])
    end

    test "rejects programs containing a slash", %{workspace: ws} do
      assert {:error, {:command_not_allowed, "/bin/echo"}} =
               Docker.exec(ws, ["/bin/echo", "x"], [])
    end

    test "rejects when the workspace has no container_id", %{workspace: ws} do
      detached = %Workspace{ws | container_id: nil}
      assert {:error, :container_not_started} = Docker.exec(detached, ["echo"], [])
    end
  end

  describe "file operations delegate to the host backend" do
    setup %{project: project} do
      {:ok, ws} = Workspaces.provision(project, sandbox_mode: "docker")
      {:ok, workspace: ws}
    end

    test "write_file then read_file round-trips via the bind-mount", %{workspace: ws} do
      assert :ok = Docker.write_file(ws, "src/hi.txt", "hi from test")
      assert {:ok, "hi from test"} = Docker.read_file(ws, "src/hi.txt")
    end

    test "list_dir returns the bind-mounted entries", %{workspace: ws} do
      :ok = Docker.write_file(ws, "a.txt", "a")
      assert {:ok, entries} = Docker.list_dir(ws, ".")
      names = Enum.map(entries, & &1.name)
      assert "a.txt" in names
    end

    test "path traversal is still blocked", %{workspace: ws} do
      assert {:error, :path_escapes_workspace} = Docker.read_file(ws, "../etc/passwd")
    end
  end

  describe "destroy/1" do
    test "removes the container and the on-disk root", %{project: project} do
      {:ok, ws} = Workspaces.provision(project, sandbox_mode: "docker")
      assert File.dir?(ws.fs_path)
      assert :ok = Workspaces.destroy(ws)
      refute File.exists?(ws.fs_path)
      assert_received {:docker_call, ["docker", "rm" | _]}
    end
  end

  describe "audit logs" do
    test "exec emits a workspace_event with backend=docker", %{project: project} do
      {:ok, ws} = Workspaces.provision(project, sandbox_mode: "docker")
      {:ok, _} = Docker.exec(ws, ["echo", "audit"], [])

      events = WorkspaceEvents.list_for_workspace(ws.id)
      exec_event = Enum.find(events, &(&1.kind == "exec"))
      assert exec_event != nil
      assert exec_event.outcome == "ok"
      assert exec_event.metadata["backend"] == "docker"
    end
  end
end
