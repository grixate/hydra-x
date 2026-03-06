defmodule HydraXWeb.PageControllerTest do
  use HydraXWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ "single-node agent control plane"
    assert body =~ "Hydra-X"
  end

  test "GET /setup", %{conn: conn} do
    conn = get(conn, ~p"/setup")
    assert html_response(conn, 200) =~ "Primary provider"
  end
end
