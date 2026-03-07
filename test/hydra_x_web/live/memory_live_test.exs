defmodule HydraXWeb.MemoryLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Memory
  alias HydraX.Runtime

  test "memory page can create and update a memory", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"save_memory\"]", %{
      "memory" => %{
        "agent_id" => to_string(agent.id),
        "type" => "Fact",
        "importance" => "0.8",
        "content" => "The control plane can curate memory entries."
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Memory saved"
    assert html =~ "The control plane can curate memory entries."

    [memory | _] = Memory.list_memories(agent_id: agent.id, limit: 5)

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{memory.id}"]))
    |> render_click()

    view
    |> form("form[phx-submit=\"save_memory\"]", %{
      "memory" => %{
        "agent_id" => to_string(agent.id),
        "type" => "Fact",
        "importance" => "0.9",
        "content" => "The control plane can edit memory entries."
      }
    })
    |> render_submit()

    updated = Memory.get_memory!(memory.id)
    assert updated.content == "The control plane can edit memory entries."
    assert updated.importance == 0.9
  end

  test "memory page can link selected memories", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, first} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Memory linking is available.",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, second} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Keep memory relationships useful.",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{first.id}"]))
    |> render_click()

    view
    |> form("form[phx-submit=\"link_memory\"]", %{
      "edge" => %{
        "to_memory_id" => to_string(second.id),
        "kind" => "supports",
        "weight" => "1.0"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Memory link saved"
    assert html =~ "supports"
    assert Enum.any?(Memory.list_edges_for(first.id), &(&1.to_memory_id == second.id))
  end

  test "memory page can filter memories by type and search", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _fact} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Filterable fact memory",
        importance: 0.9,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _goal} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Filterable goal memory",
        importance: 0.3,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"filter_memories\"]", %{
      "filters" => %{
        "query" => "fact",
        "agent_id" => to_string(agent.id),
        "type" => "Fact",
        "min_importance" => "0.8"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Filterable fact memory"
    refute html =~ "Filterable goal memory"
  end

  test "memory page can delete a memory and its link", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, first} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Delete me",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, second} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Keep me",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, edge} =
      Memory.link_memories(%{
        from_memory_id: first.id,
        to_memory_id: second.id,
        kind: "supports",
        weight: 1.0
      })

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{first.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-click="delete_edge"][phx-value-id="#{edge.id}"]))
    |> render_click()

    assert Memory.list_edges_for(first.id) == []

    view
    |> element(~s(button[phx-click="delete_memory"][phx-value-id="#{first.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Memory deleted"
    refute html =~ "Delete me"
    assert_raise Ecto.NoResultsError, fn -> Memory.get_memory!(first.id) end
  end
end
