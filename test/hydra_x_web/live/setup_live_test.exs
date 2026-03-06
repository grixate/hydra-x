defmodule HydraXWeb.SetupLiveTest do
  use HydraXWeb.ConnCase

  test "setup page renders preview readiness report", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/setup")

    assert html =~ "Install preflight"
    assert html =~ "Operator password configured"
    assert html =~ "Public URL points beyond localhost"
  end
end
