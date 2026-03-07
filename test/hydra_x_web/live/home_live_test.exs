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

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Memory triage"
    assert html =~ "Conflicted"
    assert html =~ "Daily backups should be authoritative."
    assert html =~ "Recent guardrail activity"

    assert Enum.any?(Safety.recent_events(agent.id, 10), fn event ->
             event.category == "memory" and event.message =~ "Memory conflict flagged"
           end)
  end
end
