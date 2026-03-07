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
