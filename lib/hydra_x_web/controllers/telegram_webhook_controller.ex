defmodule HydraXWeb.TelegramWebhookController do
  use HydraXWeb, :controller

  def create(conn, params) do
    case HydraX.Gateway.dispatch_telegram_update(params) do
      :ok ->
        json(conn, %{ok: true})

      {:error, :telegram_not_configured} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{ok: false, error: "telegram_not_configured"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{ok: false, error: inspect(reason)})
    end
  end
end
