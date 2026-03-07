defmodule HydraXWeb.AgentsLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

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
    |> form("form", %{
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
end
