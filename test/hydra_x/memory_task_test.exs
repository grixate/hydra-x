defmodule HydraX.MemoryTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Memory
  alias HydraX.Runtime

  test "memory task can create, update, link, and sync memory" do
    Mix.Task.reenable("hydra_x.memory")
    agent = create_agent()

    create_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run([
          "create",
          "Fact",
          "Hydra-X stores typed memories.",
          "--agent",
          agent.slug
        ])
      end)

    assert create_output =~ "memory="
    [memory] = Memory.list_memories(agent_id: agent.id, limit: 5)

    Mix.Task.reenable("hydra_x.memory")

    update_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run([
          "update",
          to_string(memory.id),
          "Hydra-X stores operator-curated typed memories.",
          "--importance",
          "0.9"
        ])
      end)

    assert update_output =~ "memory=#{memory.id}"
    memory = Memory.get_memory!(memory.id)
    assert memory.importance == 0.9

    {:ok, other} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Maintain useful memory links.",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    Mix.Task.reenable("hydra_x.memory")

    link_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run([
          "link",
          to_string(memory.id),
          to_string(other.id),
          "supports"
        ])
      end)

    assert link_output =~ "edge="
    assert Enum.any?(Memory.list_edges_for(memory.id), &(&1.kind == "supports"))

    Mix.Task.reenable("hydra_x.memory")

    sync_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run(["sync", "--agent", agent.slug])
      end)

    assert sync_output =~ "path="
  end

  test "memory task can filter memory by type, agent, and search" do
    Mix.Task.reenable("hydra_x.memory")
    agent = create_agent()
    other_agent = create_agent()

    {:ok, _fact} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Hydra-X retains filtered facts.",
        importance: 0.9,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _goal} =
      Memory.create_memory(%{
        agent_id: other_agent.id,
        type: "Goal",
        content: "Ignore this goal.",
        importance: 0.4,
        last_seen_at: DateTime.utc_now()
      })

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run([
          "--agent",
          agent.slug,
          "--type",
          "Fact",
          "--search",
          "filtered",
          "--min_importance",
          "0.8"
        ])
      end)

    assert output =~ "\tFact\tactive\t0.9\tHydra-X retains filtered facts."
    refute output =~ "Ignore this goal."
  end

  test "memory task can delete memories and links" do
    Mix.Task.reenable("hydra_x.memory")
    agent = create_agent()

    {:ok, memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Disposable memory",
        importance: 0.5,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, other} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Disposable linked memory",
        importance: 0.6,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, edge} =
      Memory.link_memories(%{
        from_memory_id: memory.id,
        to_memory_id: other.id,
        kind: "supports",
        weight: 1.0
      })

    unlink_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run(["unlink", to_string(edge.id)])
      end)

    assert unlink_output =~ "deleted_edge=#{edge.id}"
    assert Memory.list_edges_for(memory.id) == []

    Mix.Task.reenable("hydra_x.memory")

    delete_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run(["delete", to_string(memory.id)])
      end)

    assert delete_output =~ "deleted_memory=#{memory.id}"
    assert_raise Ecto.NoResultsError, fn -> Memory.get_memory!(memory.id) end
  end

  test "memory task can reconcile memories with merge and supersede" do
    Mix.Task.reenable("hydra_x.memory")
    agent = create_agent()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Old deployment note",
        importance: 0.4,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Current deployment policy",
        importance: 0.9,
        last_seen_at: DateTime.utc_now()
      })

    merge_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run([
          "merge",
          to_string(source.id),
          to_string(target.id),
          "--content",
          "Merged deployment policy"
        ])
      end)

    assert merge_output =~ "merged=#{source.id}->#{target.id}"
    assert Memory.get_memory!(source.id).status == "merged"
    assert Memory.get_memory!(target.id).content == "Merged deployment policy"

    Mix.Task.reenable("hydra_x.memory")

    {:ok, superseded} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Deprecated note",
        importance: 0.2,
        last_seen_at: DateTime.utc_now()
      })

    supersede_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Memory.run([
          "supersede",
          to_string(superseded.id),
          to_string(target.id)
        ])
      end)

    assert supersede_output =~ "superseded=#{superseded.id}->#{target.id}"
    assert Memory.get_memory!(superseded.id).status == "superseded"
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Memory Task Agent #{unique}",
        slug: "memory-task-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-memory-task-#{unique}"),
        description: "memory task test",
        is_default: false
      })

    agent
  end
end
