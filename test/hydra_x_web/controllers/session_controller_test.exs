defmodule HydraXWeb.SessionControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Accounts
  alias HydraX.Security.LoginThrottle
  alias HydraX.Safety
  alias HydraXWeb.OperatorAuth

  setup do
    LoginThrottle.reset!()
    :ok
  end

  defp create_operator!(attrs \\ %{}) do
    email =
      Map.get(attrs, :email, "operator+#{System.unique_integer([:positive])}@test.example.com")

    password = Map.get(attrs, :password, "hydra-password-123")

    {:ok, %{user: user}} =
      Accounts.register_first_operator(%{
        "email" => email,
        "display_name" => "Operator",
        "password" => password,
        "password_confirmation" => password
      })

    {user, password}
  end

  test "protected routes redirect to first-operator registration until an operator exists", %{
    conn: conn
  } do
    conn = get(conn, ~p"/setup")
    assert redirected_to(conn) == "/register"
  end

  test "first registration creates operator session and grants access", %{conn: conn} do
    conn =
      post(conn, ~p"/register", %{
        "user" => %{
          "email" => "first@test.example.com",
          "display_name" => "First Operator",
          "password" => "hydra-password-123",
          "password_confirmation" => "hydra-password-123"
        }
      })

    assert redirected_to(conn) == "/setup"
    assert get_session(conn, :hydra_user_id)
    assert is_integer(get_session(conn, :operator_recent_auth_at))

    conn = conn |> recycle() |> get(~p"/setup")
    assert html_response(conn, 200) =~ "Local operator account"
  end

  test "protected routes redirect to login after an operator exists", %{conn: conn} do
    create_operator!()

    conn = get(conn, ~p"/setup")
    assert redirected_to(conn) == "/login"
  end

  test "login grants access to protected routes", %{conn: conn} do
    {user, password} = create_operator!()

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"email" => user.email, "password" => password}
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, :hydra_user_id) == user.id
    assert is_integer(get_session(conn, :operator_recent_auth_at))

    conn = conn |> recycle() |> get(~p"/setup")
    assert html_response(conn, 200) =~ "Local operator account"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Operator login succeeded"
  end

  test "invalid login is audited", %{conn: conn} do
    {user, _password} = create_operator!()

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"email" => user.email, "password" => "bad-password"}
      })

    assert html_response(conn, 200) =~ "Operator sign-in"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.level == "warn"
    assert event.message =~ "Operator login failed"
  end

  test "login is blocked after too many failures from the same IP", %{conn: conn} do
    {user, _password} = create_operator!()

    Enum.each(1..5, fn _attempt ->
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "bad-password"}
        })

      assert html_response(conn, 200) =~ "Operator sign-in"
    end)

    blocked_conn =
      post(conn, ~p"/login", %{
        "user" => %{"email" => user.email, "password" => "bad-password"}
      })

    html = html_response(blocked_conn, 200)
    assert html =~ "Too many attempts, try again later."
    assert html =~ "Login throttle: 5 attempts per 60s window."

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Blocked operator login due to rate limit"
  end

  test "logout is audited", %{conn: conn} do
    {user, _password} = create_operator!()

    conn = conn |> init_test_session(%{}) |> OperatorAuth.log_in(user)
    conn = delete(conn, ~p"/logout")

    assert redirected_to(conn) == "/login"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.message =~ "Operator logged out"
  end

  test "expired session redirects to login and is audited", %{conn: conn} do
    {user, _password} = create_operator!()
    now = System.system_time(:second)

    conn =
      conn
      |> init_test_session(%{})
      |> OperatorAuth.log_in(user, authenticated_at: now - 90_000, last_active_at: now - 90_000)
      |> get(~p"/setup")

    assert redirected_to(conn) == "/login?expired=max_age"

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.level == "warn"
    assert event.message =~ "Operator session expired"
  end
end
