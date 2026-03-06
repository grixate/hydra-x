defmodule HydraXWeb.TelegramWebhookControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  test "rejects webhook requests with invalid secret", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "token",
        webhook_secret: "expected-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-telegram-bot-api-secret-token", "wrong-secret")
      |> post(~p"/api/telegram/webhook", %{"message" => %{"chat" => %{"id" => 1}, "text" => "hi"}})

    assert json_response(conn, 401)["error"] == "unauthorized"
  end
end
