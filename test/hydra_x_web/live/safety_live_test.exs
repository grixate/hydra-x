defmodule HydraXWeb.SafetyLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime
  alias HydraX.Safety

  test "safety page filters events by level", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    assert {:ok, _warn} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "tool",
               level: "warn",
               message: "warn event"
             })

    assert {:ok, _error} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "gateway",
               level: "error",
               message: "error event"
             })

    {:ok, view, _html} = live(conn, ~p"/safety")

    view
    |> form("form", %{"filters" => %{"level" => "error", "category" => "", "limit" => "10"}})
    |> render_submit()

    html = render(view)
    assert html =~ "error event"
    refute html =~ "warn event"
  end

  test "safety page can acknowledge and resolve incidents", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, event} =
      Safety.log_event(%{
        agent_id: agent.id,
        category: "gateway",
        level: "error",
        message: "delivery failed"
      })

    {:ok, view, _html} = live(conn, ~p"/safety")

    view
    |> element(~s(button[phx-click="acknowledge"][phx-value-id="#{event.id}"]))
    |> render_click()

    assert Safety.get_event!(event.id).status == "acknowledged"

    view
    |> element(~s(button[phx-click="resolve"][phx-value-id="#{event.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Safety event resolved"
    assert html =~ "resolved"
    assert Safety.get_event!(event.id).status == "resolved"
  end
end
