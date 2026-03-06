defmodule HydraXWeb.SessionControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

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

    conn = conn |> recycle() |> get(~p"/setup")
    assert html_response(conn, 200) =~ "Operator password"
  end
end
