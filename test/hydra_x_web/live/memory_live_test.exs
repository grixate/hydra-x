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

  test "memory page shows ranked reasons and scores for search results", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _goal} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Ship the Webchat support rollout.",
        importance: 0.8,
        metadata: %{
          "source" => "ingest",
          "source_file" => "ops-goals.md",
          "source_section" => "webchat rollout"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _fact} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Discord support rollout needs retry coverage.",
        importance: 0.5,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"filter_memories\"]", %{
      "filters" => %{
        "query" => "ops webchat goal",
        "agent_id" => to_string(agent.id),
        "type" => "",
        "status" => "active",
        "min_importance" => ""
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Ship the Webchat support rollout."
    assert html =~ "score"
    assert html =~ "embedding"
    assert html =~ "goal match"
    assert html =~ "source provenance"
    assert html =~ "ingest provenance"
  end

  test "memory page shows embedding posture for the current filter scope", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Embedding posture should be visible on the memory page.",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _view, html} = live(conn, ~p"/memory")

    assert html =~ "Embedding posture"
    assert html =~ "backend local_hash_v1"
    assert html =~ "Fallback writes"
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

  test "memory page can reconcile a memory into another entry", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Deprecated workflow",
        importance: 0.4,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Current workflow",
        importance: 0.9,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{source.id}"]))
    |> render_click()

    view
    |> form("form[phx-submit=\"reconcile_memory\"]", %{
      "reconcile" => %{
        "mode" => "supersede",
        "target_id" => to_string(target.id),
        "content" => ""
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Memory reconciled"
    assert html =~ "Current workflow"
    assert Memory.get_memory!(source.id).status == "superseded"
    assert Enum.any?(Memory.list_edges_for(target.id), &(&1.kind == "supersedes"))

    view
    |> form("form[phx-submit=\"filter_memories\"]", %{
      "filters" => %{
        "query" => "",
        "agent_id" => to_string(agent.id),
        "type" => "",
        "status" => "superseded",
        "min_importance" => ""
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Deprecated workflow"
  end

  test "memory page can mark memories as conflicted and switch to conflicted view", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Daily backup cadence is preferred.",
        importance: 0.6,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Weekly backup cadence is preferred.",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{source.id}"]))
    |> render_click()

    view
    |> form("form[phx-submit=\"reconcile_memory\"]", %{
      "reconcile" => %{
        "mode" => "conflict",
        "target_id" => to_string(target.id),
        "content" => "Operator guidance is inconsistent."
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Memory reconciled"
    assert html =~ "Daily backup cadence is preferred."
    assert html =~ "conflicted"
    assert Memory.get_memory!(source.id).status == "conflicted"
    assert Memory.get_memory!(target.id).status == "conflicted"
    assert Enum.any?(Memory.list_edges_for(source.id), &(&1.kind == "contradicts"))
  end

  test "memory page can resolve a conflicted memory in favor of the selected entry", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, winner} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Daily backup cadence is canonical.",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, loser} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Weekly backup cadence is canonical.",
        importance: 0.6,
        last_seen_at: DateTime.utc_now()
      })

    assert {:ok, _result} =
             Memory.conflict_memory!(winner.id, loser.id, reason: "Operator guidance diverged")

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"filter_memories\"]", %{
      "filters" => %{
        "query" => "",
        "agent_id" => to_string(agent.id),
        "type" => "",
        "status" => "conflicted",
        "min_importance" => ""
      }
    })
    |> render_submit()

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{winner.id}"]))
    |> render_click()

    view
    |> form("form[phx-submit=\"reconcile_memory\"]", %{
      "reconcile" => %{
        "mode" => "resolve_conflict",
        "target_id" => to_string(loser.id),
        "content" => "Daily backup cadence remains canonical."
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Memory reconciled"
    assert html =~ "Daily backup cadence remains canonical."

    assert has_element?(
             view,
             ~s(select[name="filters[status]"] option[selected][value="active"])
           )

    assert Memory.get_memory!(winner.id).status == "active"
    assert Memory.get_memory!(loser.id).status == "superseded"
  end

  test "memory page can ingest a file from the agent ingest directory", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "ops.md"), "# Ops\n\nHydra-X can ingest workspace files.")

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"ingest_file\"]", %{
      "ingest" => %{"filename" => "ops.md"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Ingested ops.md"
    assert html =~ "ops.md"
    assert html =~ "Recent ingest runs"
    assert html =~ "imported"

    assert Enum.any?(
             Memory.list_memories(agent_id: agent.id, status: "active", limit: 20),
             &String.contains?(&1.content, "Hydra-X can ingest workspace files.")
           )
  end

  test "memory page reports unchanged ingest runs", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "ops.md"), "# Ops\n\nHydra-X can ingest workspace files.")

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"ingest_file\"]", %{
      "ingest" => %{"filename" => "ops.md", "force" => "false"}
    })
    |> render_submit()

    view
    |> form("form[phx-submit=\"ingest_file\"]", %{
      "ingest" => %{"filename" => "ops.md", "force" => "false"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Ingest skipped for ops.md: unchanged document"
    assert html =~ "status"
    assert html =~ "skipped"
    assert html =~ "reason unchanged_document"
  end

  test "memory page shows ingest provenance and restored runs after reimport", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)

    File.write!(
      Path.join(ingest_dir, "ops.md"),
      "# Ops\n\nHydra-X can restore archived ingest chunks."
    )

    {:ok, view, _html} = live(conn, ~p"/memory")

    view
    |> form("form[phx-submit=\"ingest_file\"]", %{
      "ingest" => %{"filename" => "ops.md", "force" => "false"}
    })
    |> render_submit()

    assert {:ok, _count} = Runtime.archive_file(agent.id, "ops.md")

    view
    |> form("form[phx-submit=\"ingest_file\"]", %{
      "ingest" => %{"filename" => "ops.md", "force" => "false"}
    })
    |> render_submit()

    restored =
      Memory.list_memories(agent_id: agent.id, status: "active", limit: 20)
      |> Enum.find(&String.contains?(&1.content, "restore archived ingest chunks"))

    view
    |> element(~s(button[phx-click="select_memory"][phx-value-id="#{restored.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "1 restored"
    assert html =~ "Ingest provenance"
    assert html =~ "Source file"
    assert html =~ "ops.md"
    assert html =~ "Recent runs for this source"
    assert html =~ "restored 1"
  end
end
