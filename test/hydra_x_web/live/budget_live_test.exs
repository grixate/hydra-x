defmodule HydraXWeb.BudgetLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Budget
  alias HydraX.Runtime

  test "budget page can switch agents and update policy", %{conn: conn} do
    default_agent = Runtime.ensure_default_agent!()

    {:ok, second_agent} =
      Runtime.save_agent(%{
        name: "Second Budget Agent",
        slug: "second-budget-agent",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-second-budget-agent"),
        description: "second budget agent",
        is_default: false
      })

    Budget.ensure_policy!(default_agent.id)
    Budget.ensure_policy!(second_agent.id)

    {:ok, view, _html} = live(conn, ~p"/budget")

    view
    |> form("form[phx-change=\"select_agent\"]", %{
      "agent" => %{"agent_id" => to_string(second_agent.id)}
    })
    |> render_change()

    view
    |> form("form[phx-submit=\"save\"]", %{
      "policy" => %{
        "daily_limit" => "9999",
        "conversation_limit" => "2222",
        "soft_warning_at" => "0.7",
        "hard_limit_action" => "warn",
        "enabled" => "true"
      }
    })
    |> render_submit()

    policy = Budget.get_policy(second_agent.id)
    assert policy.daily_limit == 9_999
    assert policy.conversation_limit == 2_222
    assert policy.hard_limit_action == "warn"

    html = render(view)
    assert html =~ "Budget policy updated"
    assert html =~ "Recent token usage"
  end
end
