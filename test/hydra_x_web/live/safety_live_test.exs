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
end
