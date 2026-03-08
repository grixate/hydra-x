defmodule HydraX.Gateway.Adapters.Slack do
  @moduledoc """
  Slack adapter implementing the Gateway.Adapter behaviour.

  Handles Slack Events API payloads and delivers responses via
  the Slack Web API (chat.postMessage).
  """

  @behaviour HydraX.Gateway.Adapter

  @slack_api "https://slack.com/api"

  @impl true
  def connect(%{"bot_token" => token} = config) when is_binary(token) and token != "" do
    {:ok,
     %{
       bot_token: token,
       signing_secret: config["signing_secret"],
       deliver: config["deliver"]
     }}
  end

  def connect(_config), do: {:error, :missing_bot_token}

  @impl true
  def handle_event(%{"type" => "url_verification", "challenge" => _challenge}, state) do
    # Slack verification challenge — handled at the controller level
    {:messages, [], state}
  end

  def handle_event(
        %{
          "type" => "event_callback",
          "event" => %{"type" => "message", "channel" => channel_id, "text" => text} = event
        } = payload,
        state
      )
      when is_binary(text) and text != "" do
    # Skip bot messages to avoid loops
    if event["bot_id"] || event["subtype"] do
      {:messages, [], state}
    else
      message = %{
        channel: "slack",
        external_ref: channel_id,
        content: text,
        metadata: %{
          raw: payload,
          user: event["user"],
          team: payload["team_id"],
          ts: event["ts"],
          thread_ts: event["thread_ts"]
        }
      }

      {:messages, [message], state}
    end
  end

  def handle_event(_event, state), do: {:messages, [], state}

  @impl true
  def send_response(%{content: content, external_ref: channel_id}, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(content, channel_id, token, deliver)
  end

  @doc """
  Verify a Slack request signature.

  Uses HMAC-SHA256 with the signing secret to verify the request came from Slack.
  """
  def verify_signature(body, timestamp, signature, signing_secret)
      when is_binary(body) and is_binary(signing_secret) do
    base_string = "v0:#{timestamp}:#{body}"

    expected =
      "v0=" <>
        (:crypto.mac(:hmac, :sha256, signing_secret, base_string)
         |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify_signature(_body, _timestamp, _signature, _signing_secret) do
    {:error, :missing_signing_params}
  end

  # -- Private --

  defp do_send_response(content, channel_id, _token, deliver) when is_function(deliver, 1) do
    case deliver.(%{content: content, external_ref: channel_id}) do
      :ok -> {:ok, %{channel: "slack"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, Map.put_new(metadata, :channel, "slack")}
      other -> other
    end
  end

  defp do_send_response(content, channel_id, token, _deliver) do
    case Req.post(
           url: "#{@slack_api}/chat.postMessage",
           headers: [{"authorization", "Bearer #{token}"}],
           json: %{channel: channel_id, text: content}
         ) do
      {:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}} ->
        {:ok, %{channel: "slack", provider_message_id: ts}}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, {:slack_error, error}}

      {:ok, %{status: status}} ->
        {:error, {:slack_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
