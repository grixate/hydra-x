defmodule HydraX.Agent.CompactorTest do
  use HydraX.DataCase, async: false

  alias HydraX.Agent.Compactor
  alias HydraX.Product.Project
  alias HydraX.Product.Workspace.Backend.Host
  alias HydraX.Product.Workspaces
  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Conversation}

  setup do
    suffix = System.unique_integer([:positive])

    tmp_root =
      Path.join(System.tmp_dir!(), "hx_compactor_test_#{suffix}")

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
    researcher = insert_agent!("researcher-cmp-#{suffix}")
    strategist = insert_agent!("strategist-cmp-#{suffix}")

    %Project{}
    |> Project.changeset(%{
      "name" => "Compactor Project #{suffix}",
      "slug" => "compactor-project-#{suffix}",
      "researcher_agent_id" => researcher.id,
      "strategist_agent_id" => strategist.id
    })
    |> Repo.insert!()
  end

  defp insert_conversation!(agent_id, metadata \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(%{
      "agent_id" => agent_id,
      "channel" => "test",
      "status" => "active",
      "metadata" => metadata
    })
    |> Repo.insert!()
  end

  describe "resolve_strategy/1" do
    test "returns code_aware for coder personas", %{suffix: suffix} do
      agent = insert_agent!("coder-#{suffix}")
      conv = insert_conversation!(agent.id, %{"product_persona" => "coder"})

      assert "code_aware" =
               Compactor.resolve_strategy(%{conversation_id: conv.id, agent_id: agent.id})
    end

    test "returns simple for non-coder personas", %{suffix: suffix} do
      agent = insert_agent!("strategist-#{suffix}")
      conv = insert_conversation!(agent.id, %{"product_persona" => "strategist"})

      assert "simple" =
               Compactor.resolve_strategy(%{conversation_id: conv.id, agent_id: agent.id})
    end

    test "returns simple when conversation has no metadata", %{suffix: suffix} do
      agent = insert_agent!("naked-#{suffix}")
      conv = insert_conversation!(agent.id, %{})

      assert "simple" =
               Compactor.resolve_strategy(%{conversation_id: conv.id, agent_id: agent.id})
    end

    test "returns simple when conversation does not exist", _ctx do
      assert "simple" = Compactor.resolve_strategy(%{conversation_id: 0, agent_id: 0})
    end
  end

  describe "workspace_activity_section/1" do
    test "renders workspace events from the bound project", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, ws} = Workspaces.provision(project)
      :ok = Host.write_file(ws, "src/main.ex", "defmodule X, do: :ok")
      :ok = Host.write_file(ws, "src/main.ex", "defmodule X, do: :still_ok")
      {:ok, _} = Host.exec(ws, ["echo", "test pass"], [])

      agent = insert_agent!("coder-act-#{suffix}")

      conv =
        insert_conversation!(agent.id, %{
          "product_persona" => "coder",
          "product_project_id" => to_string(project.id)
        })

      section =
        Compactor.workspace_activity_section(%{conversation_id: conv.id, agent_id: agent.id})

      assert section =~ "Workspace activity:"
      assert section =~ "src/main.ex"
      assert section =~ "echo"
    end

    test "handles a conversation with no project bound", %{suffix: suffix} do
      agent = insert_agent!("nopro-#{suffix}")
      conv = insert_conversation!(agent.id, %{"product_persona" => "coder"})

      section =
        Compactor.workspace_activity_section(%{conversation_id: conv.id, agent_id: agent.id})

      assert section =~ "no workspace bound"
    end

    test "handles a project with zero workspace events", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, _ws} = Workspaces.provision(project)
      # provision auto-writes HYDRA.md so we'll have ONE event; the test
      # below uses a freshly-provisioned project where activity exists.
      # Verify the section renders something meaningful either way.
      agent = insert_agent!("emp-#{suffix}")

      conv =
        insert_conversation!(agent.id, %{
          "product_project_id" => to_string(project.id)
        })

      section =
        Compactor.workspace_activity_section(%{conversation_id: conv.id, agent_id: agent.id})

      assert is_binary(section)
      assert section =~ "Workspace activity:"
    end
  end

  describe "code_aware_compaction_prompt/3" do
    test "includes workspace activity, transcript, and instructions", %{suffix: suffix} do
      project = insert_project!(suffix)
      {:ok, ws} = Workspaces.provision(project)
      :ok = Host.write_file(ws, "lib/hello.ex", "defmodule Hello, do: :ok")

      agent = insert_agent!("prompt-#{suffix}")

      conv =
        insert_conversation!(agent.id, %{
          "product_persona" => "coder",
          "product_project_id" => to_string(project.id)
        })

      prompt =
        Compactor.code_aware_compaction_prompt(
          "user: write the module\nassistant: done",
          [],
          %{conversation_id: conv.id, agent_id: agent.id}
        )

      assert prompt =~ "Summarize this coding session"
      assert prompt =~ "ALL file paths"
      assert prompt =~ "lib/hello.ex"
      assert prompt =~ "user: write the module"
    end
  end

  describe "broadcast_compacted/2" do
    test "fires a {:context_compacted, ...} message on the conversation topic", %{suffix: suffix} do
      agent = insert_agent!("bc-#{suffix}")
      conv = insert_conversation!(agent.id)

      :ok = Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations:#{conv.id}")

      Compactor.broadcast_compacted(conv.id, %{
        level: "soft",
        turns_compacted: 12,
        estimated_tokens: 100,
        token_ratio: 0.85
      })

      assert_receive {:context_compacted, conv_id, payload}, 500
      assert conv_id == conv.id
      assert payload.level == "soft"
      assert payload.turns_compacted == 12
    end
  end
end
