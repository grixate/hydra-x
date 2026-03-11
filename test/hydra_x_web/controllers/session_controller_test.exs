defmodule HydraXWeb.SessionControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime
  alias HydraX.Security.LoginThrottle
  alias HydraX.Safety
  alias HydraXWeb.OperatorAuth

  setup do
    LoginThrottle.reset!()
    :ok
  end

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

  test "login is blocked after too many failures from the same IP", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    Enum.each(1..5, fn _attempt ->
      conn =
        post(conn, ~p"/login", %{
          "operator_secret" => %{"password" => "bad-password"}
        })

      assert html_response(conn, 200) =~ "Operator sign-in"
    end)

    blocked_conn =
      post(conn, ~p"/login", %{
        "operator_secret" => %{"password" => "bad-password"}
      })

    html = html_response(blocked_conn, 200)
    assert html =~ "Too many attempts, try again later."
    assert html =~ "Login throttle: 5 attempts per 60s window."

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Blocked operator login due to rate limit"
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

  test "expired session redirects to login and is audited", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    now = System.system_time(:second)

    conn =
      conn
      |> init_test_session(%{})
      |> OperatorAuth.log_in(authenticated_at: now - 90_000, last_active_at: now - 90_000)
      |> get(~p"/setup")

    assert redirected_to(conn) == "/login?expired=max_age"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.level == "warn"
    assert event.message =~ "Operator session expired"
  end

  test "reauth login preserves context and audit metadata", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    login_page = get(conn, ~p"/login?reauth=1")
    assert html_response(login_page, 200) =~ ~s(name="reauth" value="1")

    conn =
      post(conn, ~p"/login", %{
        "reauth" => "1",
        "operator_secret" => %{"password" => "hydra-password-123"}
      })

    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Signed in again."

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Operator login succeeded"
    assert event.metadata["reauth?"] == true
  end
end
