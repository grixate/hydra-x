defmodule HydraXWeb.SessionControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraXWeb.OperatorAuth

  test "protected routes stay open until an operator password is configured", %{conn: conn} do
    conn = get(conn, ~p"/setup")
    assert html_response(conn, 200) =~ "Default operator identity"
  end

  test "protected routes redirect to login after operator password is configured", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn = get(conn, ~p"/setup")
    assert redirected_to(conn) == "/login"
  end

  test "login grants access to protected routes", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn =
      post(conn, ~p"/login", %{
        "operator_secret" => %{"password" => "hydra-password-123"}
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, :operator_authenticated) == true
    assert is_integer(get_session(conn, :operator_recent_auth_at))

    conn = conn |> recycle() |> get(~p"/setup")
    assert html_response(conn, 200) =~ "Operator password"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Operator login succeeded"
  end

  test "invalid login is audited", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn =
      post(conn, ~p"/login", %{
        "operator_secret" => %{"password" => "bad-password"}
      })

    assert html_response(conn, 200) =~ "Operator sign-in"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.level == "warn"
    assert event.message =~ "Operator login failed"
  end

  test "logout is audited", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn = conn |> init_test_session(%{}) |> OperatorAuth.log_in()
    conn = delete(conn, ~p"/logout")

    assert redirected_to(conn) == "/login"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Operator logged out"
  end
end
