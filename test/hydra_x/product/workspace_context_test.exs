defmodule HydraX.Product.WorkspaceContextTest do
  use HydraX.DataCase, async: false

  alias HydraX.Product.Project
  alias HydraX.Product.Workspace.Backend.Host
  alias HydraX.Product.WorkspaceContext
  alias HydraX.Product.Workspaces
  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Conversation}

  setup do
    suffix = System.unique_integer([:positive])

    tmp_root = Path.join(System.tmp_dir!(), "hx_wsctx_#{suffix}")
    File.mkdir_p!(tmp_root)
    prev = Application.get_env(:hydra_x, :workspace_root)
    Application.put_env(:hydra_x, :workspace_root, tmp_root)

    on_exit(fn ->
      Application.put_env(:hydra_x, :workspace_root, prev)
      File.rm_rf!(tmp_root)
    end)

    {:ok, suffix: suffix}
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

  defp insert_project!(suffix) do
    researcher = insert_agent!("researcher-ctx-#{suffix}")
    strategist = insert_agent!("strategist-ctx-#{suffix}")

    %Project{}
    |> Project.changeset(%{
      "name" => "Context Project #{suffix}",
      "slug" => "context-project-#{suffix}",
      "researcher_agent_id" => researcher.id,
      "strategist_agent_id" => strategist.id
    })
    |> Repo.insert!()
  end

  describe "load/1" do
    test "returns the auto-written HYDRA.md after provisioning", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, _ws} = Workspaces.provision(project)

      entries = WorkspaceContext.load(project.id)
      assert [%{file: "HYDRA.md", content: content}] = entries
      assert content =~ "Project Instructions"
    end

    test "loads multiple instruction files when present", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, ws} = Workspaces.provision(project)
      :ok = Host.write_file(ws, "AGENTS.md", "# Agents\n\nbe nice")
      :ok = Host.write_file(ws, "CLAUDE.md", "# Claude\n\nbe terse")

      entries = WorkspaceContext.load(project.id)
      names = Enum.map(entries, & &1.file) |> Enum.sort()
      assert names == ["AGENTS.md", "CLAUDE.md", "HYDRA.md"]
    end

    test "caps oversized files with a truncation marker", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, ws} = Workspaces.provision(project)

      # 50KB of content — over the 32KB cap.
      huge = String.duplicate("x", 50_000)
      :ok = Host.write_file(ws, "AGENTS.md", huge)

      [_hydra, agents] = WorkspaceContext.load(project.id)
      assert byte_size(agents.content) < 50_000
      assert agents.content =~ "truncated"
    end

    test "skips empty files", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, ws} = Workspaces.provision(project)
      :ok = Host.write_file(ws, "AGENTS.md", "")

      entries = WorkspaceContext.load(project.id)
      names = Enum.map(entries, & &1.file)
      refute "AGENTS.md" in names
    end

    test "returns [] when the project has no workspace", %{suffix: suffix} do
      project = insert_project!(suffix)
      assert WorkspaceContext.load(project.id) == []
    end

    test "returns [] for invalid project ids" do
      assert WorkspaceContext.load(0) == []
      assert WorkspaceContext.load(nil) == []
      assert WorkspaceContext.load("nope") == []
    end
  end

  describe "format/1" do
    test "produces a multi-section markdown blob", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, ws} = Workspaces.provision(project)
      :ok = Host.write_file(ws, "AGENTS.md", "be precise")

      formatted = WorkspaceContext.format(project.id)
      assert formatted =~ "## HYDRA.md"
      assert formatted =~ "## AGENTS.md"
      assert formatted =~ "be precise"
      assert formatted =~ "---"
    end

    test "returns empty string when nothing is loaded", %{suffix: suffix} do
      project = insert_project!(suffix)
      assert WorkspaceContext.format(project.id) == ""
    end
  end

  describe "format_for_conversation/1" do
    test "extracts product_project_id from conversation metadata", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, _ws} = Workspaces.provision(project)

      agent = insert_agent!("conv-ctx-#{suffix}")

      conv =
        %Conversation{}
        |> Conversation.changeset(%{
          "agent_id" => agent.id,
          "channel" => "test",
          "status" => "active",
          "metadata" => %{"product_project_id" => to_string(project.id)}
        })
        |> Repo.insert!()

      formatted = WorkspaceContext.format_for_conversation(conv)
      assert formatted =~ "## HYDRA.md"
    end

    test "returns empty string when no project is bound", %{suffix: suffix} do
      agent = insert_agent!("nopro-ctx-#{suffix}")

      conv =
        %Conversation{}
        |> Conversation.changeset(%{
          "agent_id" => agent.id,
          "channel" => "test",
          "status" => "active",
          "metadata" => %{}
        })
        |> Repo.insert!()

      assert WorkspaceContext.format_for_conversation(conv) == ""
    end

    test "tolerates non-map metadata" do
      assert WorkspaceContext.format_for_conversation(%{}) == ""
      assert WorkspaceContext.format_for_conversation(nil) == ""
    end
  end
end
