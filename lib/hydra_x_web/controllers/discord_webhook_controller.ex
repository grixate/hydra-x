defmodule HydraXWeb.DiscordWebhookController do
  use HydraXWeb, :controller

  def create(conn, params) do
    # Handle Discord PING interaction (type 1) for webhook verification
    if params["type"] == 1 do
      json(conn, %{type: 1})
    else
      with {:ok, _config} <- authorize(conn) do
        case HydraX.Gateway.dispatch_discord_update(params) do
          :ok ->
            json(conn, %{ok: true})

          {:error, :discord_not_configured} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{ok: false, error: "discord_not_configured"})

          {:error, reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{ok: false, error: inspect(reason)})
        end
      else
        {:error, :unauthorized} ->
          conn
          |> put_status(:unauthorized)
          |> json(%{ok: false, error: "unauthorized"})
      end
    end
  end

  defp authorize(conn) do
    case HydraX.Runtime.enabled_discord_config() do
      nil ->
        {:ok, nil}

      %{webhook_secret: nil} = config ->
        {:ok, config}

      %{webhook_secret: ""} = config ->
        {:ok, config}

      %{webhook_secret: expected} = config ->
        provided = get_req_header(conn, "x-discord-webhook-secret") |> List.first()
        if provided == expected, do: {:ok, config}, else: {:error, :unauthorized}
    end
  end
end
