defmodule HydraX.Product.WorkspaceTest do
  use HydraX.DataCase, async: false

  alias HydraX.Product.Project
  alias HydraX.Product.Tools.CodeRead
  alias HydraX.Product.Workspace
  alias HydraX.Product.Workspace.Backend.Host
  alias HydraX.Product.WorkspaceEvents
  alias HydraX.Product.Workspaces
  alias HydraX.Repo
  alias HydraX.Runtime.AgentProfile

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "hydra_x_ws_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_root)
    prev = Application.get_env(:hydra_x, :workspace_root)
    Application.put_env(:hydra_x, :workspace_root, tmp_root)

    on_exit(fn ->
      Application.put_env(:hydra_x, :workspace_root, prev)
      File.rm_rf!(tmp_root)
    end)

    project = insert_minimal_project!()
    {:ok, %{project: project, tmp_root: tmp_root}}
  end

  # Bypasses Product.create_project (which is heavy and currently flaky in the
  # sandbox due to escaping Tasks). We only need a Project row with the two
  # required FK agent profiles to exercise the workspace stack.
  defp insert_minimal_project!() do
    suffix = System.unique_integer([:positive])
    researcher = insert_agent!("researcher-#{suffix}")
    strategist = insert_agent!("strategist-#{suffix}")

    %Project{}
    |> Project.changeset(%{
      "name" => "Workspace Smoke #{suffix}",
      "slug" => "workspace-smoke-#{suffix}",
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

  describe "provision/1" do
    test "creates the row, the on-disk root, and a default HYDRA.md", %{project: project, tmp_root: tmp_root} do
      assert {:ok, %Workspace{} = ws} = Workspaces.provision(project)
      assert ws.status == "ready"
      assert ws.fs_path == Path.join(tmp_root, Integer.to_string(project.id))
      assert File.dir?(ws.fs_path)
      hydra_md = Path.join(ws.fs_path, "HYDRA.md")
      assert File.regular?(hydra_md)
      assert File.read!(hydra_md) =~ "Project Instructions"
    end

    test "is idempotent — re-provisioning returns the existing row and preserves HYDRA.md", %{project: project} do
      {:ok, ws1} = Workspaces.provision(project)
      File.write!(Path.join(ws1.fs_path, "HYDRA.md"), "## Custom\n")

      {:ok, ws2} = Workspaces.provision(project)
      assert ws2.id == ws1.id
      assert File.read!(Path.join(ws2.fs_path, "HYDRA.md")) == "## Custom\n"
    end
  end

  describe "Backend.Host file operations" do
    setup %{project: project} do
      {:ok, ws} = Workspaces.provision(project)
      {:ok, workspace: ws}
    end

    test "write_file then read_file round-trips", %{workspace: ws} do
      assert :ok = Host.write_file(ws, "src/main.ts", "console.log('hi');\n")
      assert {:ok, "console.log('hi');\n"} = Host.read_file(ws, "src/main.ts")
    end

    test "list_dir returns sorted entries with type", %{workspace: ws} do
      :ok = Host.write_file(ws, "a.txt", "a")
      :ok = Host.write_file(ws, "b/c.txt", "c")
      assert {:ok, entries} = Host.list_dir(ws, ".")
      names = Enum.map(entries, & &1.name) |> Enum.sort()
      assert "a.txt" in names
      assert "b" in names
      assert "HYDRA.md" in names
    end

    test "safe_join rejects path traversal", %{workspace: ws} do
      assert {:error, :path_escapes_workspace} = Host.read_file(ws, "../etc/passwd")
      assert {:error, :path_escapes_workspace} = Host.write_file(ws, "../escaped", "x")
    end

    test "safe_join allows nested paths", %{workspace: ws} do
      assert {:ok, _} = Host.safe_join(ws, "deep/nested/file.txt")
    end

    test "safe_join blocks a symlink whose target escapes the workspace", %{workspace: ws} do
      # Create a symlink inside the workspace that points at /etc/passwd.
      link = Path.join(ws.fs_path, "evil-link")
      File.ln_s!("/etc/passwd", link)

      assert {:error, :path_escapes_workspace} = Host.read_file(ws, "evil-link")
    end

    test "safe_join allows a symlink whose target stays inside the workspace", %{workspace: ws} do
      :ok = Host.write_file(ws, "real-file.txt", "real content")
      link = Path.join(ws.fs_path, "alias")
      File.ln_s!(Path.join(ws.fs_path, "real-file.txt"), link)

      assert {:ok, "real content"} = Host.read_file(ws, "alias")
    end
  end

  describe "Backend.Host exec" do
    setup %{project: project} do
      {:ok, ws} = Workspaces.provision(project)
      {:ok, workspace: ws}
    end

    test "runs an allowlisted command and returns the output", %{workspace: ws} do
      assert {:ok, %{exit_code: 0, stdout: out}} = Host.exec(ws, ["echo", "hi"], [])
      assert String.trim(out) == "hi"
    end

    test "rejects commands not in the allowlist", %{workspace: ws} do
      assert {:error, {:command_not_allowed, "curl"}} = Host.exec(ws, ["curl", "evil"], [])
    end

    test "rejects program names containing a slash", %{workspace: ws} do
      assert {:error, {:command_not_allowed, "/bin/echo"}} = Host.exec(ws, ["/bin/echo", "x"], [])
    end

    test "rejects non-binary arguments", %{workspace: ws} do
      assert {:error, :invalid_arguments} = Host.exec(ws, ["echo", 123], [])
    end
  end

  describe "audit log" do
    setup %{project: project} do
      {:ok, ws} = Workspaces.provision(project)
      {:ok, workspace: ws}
    end

    test "every operation appends an event row", %{workspace: ws} do
      :ok = Host.write_file(ws, "x.txt", "y")
      {:ok, _} = Host.read_file(ws, "x.txt")
      {:ok, _} = Host.list_dir(ws, ".")
      {:ok, _} = Host.exec(ws, ["echo", "ok"], [])

      events = WorkspaceEvents.list_for_workspace(ws.id)
      kinds = Enum.map(events, & &1.kind) |> Enum.sort()

      assert "write" in kinds
      assert "read" in kinds
      assert "list" in kinds
      assert "exec" in kinds
      assert Enum.all?(events, &(&1.outcome == "ok"))
    end

    test "errors are recorded with outcome=error", %{workspace: ws} do
      {:error, _} = Host.read_file(ws, "../escape")
      {:error, _} = Host.exec(ws, ["curl", "x"], [])

      events = WorkspaceEvents.list_for_workspace(ws.id)
      errors = Enum.filter(events, &(&1.outcome == "error"))
      assert length(errors) >= 2
    end
  end

  describe "CodeRead tool end-to-end" do
    test "resolves the workspace from product_project_id and reads a file", %{project: project} do
      {:ok, ws} = Workspaces.provision(project)
      :ok = Host.write_file(ws, "README.md", "# hello\n")

      context = %{product_project_id: project.id}

      assert {:ok, %{path: "README.md", excerpt: "# hello\n"}} =
               CodeRead.execute(%{"path" => "README.md"}, context)
    end

    test "returns an error when no project_id is in context", %{project: _project} do
      assert {:error, :missing_project_id} =
               CodeRead.execute(%{"path" => "README.md"}, %{})
    end
  end

  describe "destroy/1" do
    test "removes the on-disk root and the row", %{project: project} do
      {:ok, ws} = Workspaces.provision(project)
      assert File.dir?(ws.fs_path)
      assert :ok = Workspaces.destroy(ws)
      refute File.exists?(ws.fs_path)
      assert Workspaces.get_for_project(project.id) == nil
    end
  end
end
