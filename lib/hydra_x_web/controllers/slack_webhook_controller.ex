defmodule HydraXWeb.SlackWebhookController do
  use HydraXWeb, :controller

  alias HydraX.Gateway.Adapters.Slack

  def create(conn, params) do
    # Handle Slack URL verification challenge
    if params["type"] == "url_verification" do
      json(conn, %{challenge: params["challenge"]})
    else
      with {:ok, _config} <- authorize(conn) do
        case HydraX.Gateway.dispatch_slack_update(params) do
          :ok ->
            json(conn, %{ok: true})

          {:error, :slack_not_configured} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{ok: false, error: "slack_not_configured"})

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
    case HydraX.Runtime.enabled_slack_config() do
      nil ->
        {:ok, nil}

      %{signing_secret: nil} = config ->
        {:ok, config}

      %{signing_secret: ""} = config ->
        {:ok, config}

      %{signing_secret: secret} = config ->
        timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
        signature = get_req_header(conn, "x-slack-signature") |> List.first()

        # Slack sends the raw body, which we need for signature verification
        # The body is read from the conn assigns if available (set by a plug)
        body = conn.assigns[:raw_body] || ""

        case Slack.verify_signature(body, timestamp, signature, secret) do
          :ok -> {:ok, config}
          {:error, _reason} -> {:error, :unauthorized}
        end
    end
  end
end
