defmodule HydraX.Runtime.SessionBranchesTest do
  use HydraX.DataCase, async: false

  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Conversation, ConversationBranch, Conversations, SessionBranches, Turn}

  setup do
    suffix = System.unique_integer([:positive])

    agent =
      %AgentProfile{}
      |> AgentProfile.changeset(%{
        "name" => "branchy-#{suffix}",
        "slug" => "branchy-#{suffix}",
        "workspace_root" => Path.join(System.tmp_dir!(), "hx_branch_#{suffix}")
      })
      |> Repo.insert!()

    conversation =
      %Conversation{}
      |> Conversation.changeset(%{"agent_id" => agent.id, "channel" => "test", "status" => "active"})
      |> Repo.insert!()

    {:ok, conversation: conversation, agent: agent}
  end

  describe "ensure_main_branch/1" do
    test "creates a main branch and sets it active when missing", %{conversation: conv} do
      branch = SessionBranches.ensure_main_branch(conv.id)
      assert %ConversationBranch{label: "main"} = branch
      assert is_binary(branch.branch_uuid)

      reloaded = Repo.get!(Conversation, conv.id)
      assert reloaded.active_branch_id == branch.branch_uuid
    end

    test "is idempotent", %{conversation: conv} do
      b1 = SessionBranches.ensure_main_branch(conv.id)
      b2 = SessionBranches.ensure_main_branch(conv.id)
      assert b1.id == b2.id
    end
  end

  describe "append_turn / list_turns active-branch behaviour" do
    test "appended turns land in the active branch with branch-local sequence", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "hi", "kind" => "message"})
      {:ok, t2} = Conversations.append_turn(conv, %{"role" => "assistant", "content" => "yo", "kind" => "message"})

      assert t1.sequence == 1
      assert t2.sequence == 2
      assert t1.branch_id == t2.branch_id

      turns = Conversations.list_turns(conv.id)
      assert length(turns) == 2
      assert Enum.map(turns, & &1.role) == ["user", "assistant"]
    end

    test "list_turns/2 with branch: :all returns turns from every branch", %{conversation: conv} do
      {:ok, _} = Conversations.append_turn(conv, %{"role" => "user", "content" => "main-1"})

      reloaded = Repo.get!(Conversation, conv.id)
      [t1] = Conversations.list_turns(conv.id)
      {:ok, _new_branch} = SessionBranches.fork(t1, "alt")

      reloaded_after = Repo.get!(Conversation, conv.id)
      {:ok, _} = Conversations.append_turn(reloaded_after, %{"role" => "user", "content" => "alt-1"})

      active = Conversations.list_turns(conv.id)
      all = Conversations.list_turns(conv.id, branch: :all)

      assert length(active) == 1
      assert length(all) == 2
      assert reloaded.active_branch_id != reloaded_after.active_branch_id
    end
  end

  describe "fork/2" do
    test "creates a new branch and switches to it", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "first"})
      conv1 = Repo.get!(Conversation, conv.id)

      {:ok, branch} = SessionBranches.fork(t1, "alt-approach")
      assert branch.label == "alt-approach"
      assert branch.parent_branch_id != nil
      assert branch.forked_from_sequence == 1

      conv2 = Repo.get!(Conversation, conv.id)
      assert conv2.active_branch_id == branch.branch_uuid
      assert conv2.active_branch_id != conv1.active_branch_id
    end

    test "after fork, sequence in the new branch starts at 1", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "main-1"})
      {:ok, _t2} = Conversations.append_turn(conv, %{"role" => "user", "content" => "main-2"})

      {:ok, _branch} = SessionBranches.fork(t1, "branch-a")
      conv_after = Repo.get!(Conversation, conv.id)

      {:ok, t3} = Conversations.append_turn(conv_after, %{"role" => "user", "content" => "branch-1"})
      assert t3.sequence == 1

      {:ok, t4} = Conversations.append_turn(conv_after, %{"role" => "user", "content" => "branch-2"})
      assert t4.sequence == 2

      # The original branch is untouched.
      all = Conversations.list_turns(conv.id, branch: :all)
      assert length(all) == 4
    end
  end

  describe "switch/2" do
    test "switches the active branch back and forth", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "main-1"})
      conv1 = Repo.get!(Conversation, conv.id)
      main_uuid = conv1.active_branch_id

      {:ok, branch} = SessionBranches.fork(t1, "alt")
      conv2 = Repo.get!(Conversation, conv.id)
      assert conv2.active_branch_id == branch.branch_uuid

      {:ok, _} = SessionBranches.switch(conv.id, main_uuid)
      conv3 = Repo.get!(Conversation, conv.id)
      assert conv3.active_branch_id == main_uuid
    end

    test "rejects unknown branch UUIDs", %{conversation: conv} do
      assert {:error, :branch_not_found} =
               SessionBranches.switch(conv.id, Ecto.UUID.generate())
    end
  end

  describe "tree/1" do
    test "returns turn counts per branch", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "m1"})
      {:ok, _t2} = Conversations.append_turn(conv, %{"role" => "user", "content" => "m2"})

      {:ok, _branch} = SessionBranches.fork(t1, "fork-a")
      conv_after = Repo.get!(Conversation, conv.id)
      {:ok, _} = Conversations.append_turn(conv_after, %{"role" => "user", "content" => "f1"})

      tree = SessionBranches.tree(conv.id)
      assert length(tree) == 2
      counts = Map.new(tree, fn entry -> {entry.label, entry.turn_count} end)
      assert counts["main"] == 2
      assert counts["fork-a"] == 1
    end
  end

  describe "fork/3 switch? option" do
    test "fork with switch?: false leaves the active branch unchanged", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "hi"})
      conv1 = Repo.get!(Conversation, conv.id)
      original_active = conv1.active_branch_id

      {:ok, branch} = SessionBranches.fork(t1, "saved-for-later", switch?: false)
      assert branch.label == "saved-for-later"

      conv2 = Repo.get!(Conversation, conv.id)
      assert conv2.active_branch_id == original_active
      assert conv2.active_branch_id != branch.branch_uuid
    end

    test "fork with switch?: true (default) switches active", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "hi"})

      {:ok, branch} = SessionBranches.fork(t1, "switching-branch")

      conv_after = Repo.get!(Conversation, conv.id)
      assert conv_after.active_branch_id == branch.branch_uuid
    end
  end

  describe "label uniqueness" do
    test "fork rejects a label already used by another branch", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "hi"})
      assert {:ok, _} = SessionBranches.fork(t1, "alt")
      assert {:error, %Ecto.Changeset{}} = SessionBranches.fork(t1, "alt")
    end

    test "fork rejects label='main' since main always exists", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "hi"})
      assert {:error, %Ecto.Changeset{}} = SessionBranches.fork(t1, "main")
    end
  end

  describe "branch-local uniqueness" do
    test "two branches can each hold their own sequence 1 without collision", %{conversation: conv} do
      {:ok, t1} = Conversations.append_turn(conv, %{"role" => "user", "content" => "x"})
      {:ok, _branch} = SessionBranches.fork(t1, "side")
      conv_after = Repo.get!(Conversation, conv.id)
      {:ok, t2} = Conversations.append_turn(conv_after, %{"role" => "user", "content" => "y"})

      assert t1.sequence == 1
      assert t2.sequence == 1
      assert t1.branch_id != t2.branch_id
    end
  end
end
