defmodule HydraXWeb.AgentsLiveTest do
  use HydraXWeb.ConnCase
  @moduletag seed_default_agent: false

  alias HydraX.Runtime

  setup do
    on_exit(fn ->
      Runtime.list_agents()
      |> Enum.each(fn agent -> HydraX.Agent.ensure_stopped(agent) end)
    end)

    :ok
  end

  test "agents page can edit an agent and make it default", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Ops Agent",
        slug: "ops-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-ops-agent"),
        description: "before edit",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{agent.id}"]))
    |> render_click()

    view
    |> form(~s(form[phx-submit="save"]), %{
      "agent_profile" => %{
        "name" => "Ops Agent Updated",
        "slug" => "ops-agent",
        "workspace_root" => agent.workspace_root,
        "description" => "after edit",
        "is_default" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Agent updated"
    assert html =~ "Ops Agent Updated"
    assert html =~ "default"
    assert Runtime.get_default_agent().slug == "ops-agent"
  end

  test "agents page can repair a workspace scaffold", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Repair Agent",
        slug: "repair-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-repair-agent"),
        description: "repair",
        is_default: false
      })

    soul_path = Path.join(agent.workspace_root, "SOUL.md")
    File.rm_rf!(soul_path)

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="repair_workspace"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Workspace template repaired"
    assert File.exists?(soul_path)
  end

  test "agents page can start and stop runtime", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Runtime Agent",
        slug: "runtime-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-runtime-agent"),
        description: "runtime",
        is_default: false,
        status: "paused"
      })

    {:ok, view, _html} = live(conn, ~p"/agents")
    assert render(view) =~ "runtime down"

    view
    |> element(~s(button[phx-click="start_runtime"][phx-value-id="#{agent.id}"]))
    |> render_click()

    assert Runtime.agent_runtime_status(agent.id).running

    view
    |> element(~s(button[phx-click="stop_runtime"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agent runtime stopped"
    assert html =~ "runtime down"
    refute Runtime.agent_runtime_status(agent.id).running
  end

  test "agents page can refresh a bulletin from memory", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Bulletin Agent",
        slug: "bulletin-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-bulletin-agent"),
        description: "bulletin",
        is_default: false
      })

    {:ok, _memory} =
      HydraX.Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Operators can inspect the current bulletin."
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element(~s(button[phx-click="refresh_bulletin"][phx-value-id="#{agent.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Agent bulletin refreshed"
    assert html =~ "Operators can inspect the current bulletin."
  end

  test "agents page can update a compaction policy", %{conn: conn} do
    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Compaction Agent",
        slug: "compaction-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-compaction-agent"),
        description: "compaction",
        is_default: false
      })

    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> form(~s(form[phx-submit="save_compaction_policy"]), %{
      "compaction_policy" => %{
        "agent_id" => to_string(agent.id),
        "soft" => "5",
        "medium" => "9",
        "hard" => "13"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Compaction policy updated"
    assert html =~ "Soft 5"
    assert Runtime.compaction_policy(agent.id) == %{soft: 5, medium: 9, hard: 13}
  end
end
