defmodule HydraXWeb.UserAuthAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Accounts

  setup do
    previous_env = Application.get_env(:hydra_x, :env)
    previous_bypass = Application.get_env(:hydra_x, :dev_auth_bypass)

    on_exit(fn ->
      restore_env(:env, previous_env)
      restore_env(:dev_auth_bypass, previous_bypass)
    end)
  end

  test "POST /api/v1/user_auth/register creates the first operator session", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/user_auth/register", %{
        "email" => "api-operator@test.example.com",
        "display_name" => "API Operator",
        "password" => "hydra-password-123",
        "password_confirmation" => "hydra-password-123"
      })

    body = json_response(conn, 201)
    assert body["data"]["operator"] == true
    assert get_session(conn, :hydra_user_id) == body["data"]["id"]
  end

  test "POST /api/v1/user_auth/dev_login is unavailable outside development", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/user_auth/dev_login", %{})

    assert json_response(conn, 404) == %{"error" => "not_found"}
    assert get_session(conn, :hydra_user_id) == nil
  end

  test "POST /api/v1/user_auth/dev_login signs in a dev operator when enabled", %{conn: conn} do
    Application.put_env(:hydra_x, :env, :dev)
    Application.put_env(:hydra_x, :dev_auth_bypass, true)

    conn = post(conn, ~p"/api/v1/user_auth/dev_login", %{})

    body = json_response(conn, 200)
    assert body["data"]["email"] == "dev@hydra.local"
    assert body["data"]["operator"] == true
    assert get_session(conn, :hydra_user_id) == body["data"]["id"]
  end

  test "POST /api/v1/user_auth/login signs in with local credentials", %{conn: conn} do
    user =
      create_operator_user!(email: "api-login@test.example.com", password: "hydra-password-123")

    conn =
      post(conn, ~p"/api/v1/user_auth/login", %{
        "email" => user.email,
        "password" => "hydra-password-123"
      })

    body = json_response(conn, 200)
    assert body["data"]["id"] == user.id
    assert body["data"]["operator"] == true
    assert get_session(conn, :hydra_user_id) == user.id
  end

  test "GET /api/v1/user_auth/me and logout use the session", %{conn: conn} do
    conn = register_and_log_in_operator(conn, email: "api-me@test.example.com")

    conn = get(conn, ~p"/api/v1/user_auth/me")
    body = json_response(conn, 200)
    assert body["data"]["email"] == "api-me@test.example.com"

    conn = post(conn, ~p"/api/v1/user_auth/logout")
    assert json_response(conn, 200) == %{"data" => %{"signed_out" => true}}
    assert get_session(conn, :hydra_user_id) == nil
  end

  test "POST /api/v1/user_auth/reset_password consumes a reset token", %{conn: conn} do
    user =
      create_operator_user!(email: "api-reset@test.example.com", password: "hydra-password-123")

    assert {:ok, _token, raw_token} = Accounts.issue_password_reset(user.email)

    conn =
      post(conn, ~p"/api/v1/user_auth/reset_password", %{
        "token" => raw_token,
        "password" => "hydra-password-456",
        "password_confirmation" => "hydra-password-456"
      })

    assert json_response(conn, 200) == %{"data" => %{"password_reset" => true}}
    assert {:ok, _user} = Accounts.authenticate_user(user.email, "hydra-password-456")
  end

  defp restore_env(key, nil), do: Application.delete_env(:hydra_x, key)
  defp restore_env(key, value), do: Application.put_env(:hydra_x, key, value)
end
