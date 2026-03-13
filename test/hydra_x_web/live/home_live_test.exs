defmodule HydraXWeb.HomeLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraX.Safety

  test "home page shows memory conflicts and memory safety activity", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Daily backups should be authoritative.",
        importance: 0.6,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Weekly backups should be authoritative.",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    assert {:ok, _result} =
             Memory.conflict_memory!(source.id, target.id, reason: "Open operator dispute")

    {:ok, _ranked} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Keep ranked memory provenance visible on the operator home screen.",
        importance: 0.95,
        metadata: %{
          "source_file" => "ops/home.md",
          "source_section" => "memory-ranking",
          "source_channel" => "webchat"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Memory triage"
    assert html =~ "Embedding backend"
    assert html =~ "Top ranked active memories"
    assert html =~ "Conflicted"
    assert html =~ "Daily backups should be authoritative."
    assert html =~ "Keep ranked memory provenance visible on the operator home screen."
    assert html =~ "ops/home.md"
    assert html =~ "importance"
    assert html =~ "Recent guardrail activity"

    assert Enum.any?(Safety.recent_events(agent.id, 10), fn event ->
             event.category == "memory" and event.message =~ "Memory conflict flagged"
           end)
  end
end
