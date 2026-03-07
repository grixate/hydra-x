defmodule HydraXWeb.HealthLiveTest do
  use HydraXWeb.ConnCase

  test "health page can filter readiness warnings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/health")

    view
    |> form("form[phx-submit=\"filter_health\"]", %{
      "filters" => %{
        "search" => "password",
        "check_status" => "",
        "readiness_status" => "warn",
        "required_only" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Operator password configured"
    refute html =~ "Primary provider configured"
  end
end
