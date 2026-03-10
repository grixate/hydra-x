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
          "event" => %{"type" => "message", "channel" => channel_id} = event
        } = payload,
        state
      ) do
    # Skip bot messages to avoid loops
    if event["bot_id"] || event["subtype"] do
      {:messages, [], state}
    else
      attachments = extract_attachments(event)
      content = message_content(event, attachments)

      if is_binary(content) and content != "" do
      message = %{
        channel: "slack",
        external_ref: channel_id,
        content: content,
        metadata: %{
          raw: payload,
          user: event["user"],
          team: payload["team_id"],
          ts: event["ts"],
          thread_ts: event["thread_ts"] || event["ts"],
          source_message_id: event["ts"],
          attachments: attachments
        }
      }

        {:messages, [message], state}
      else
        {:messages, [], state}
      end
    end
  end

  def handle_event(_event, state), do: {:messages, [], state}

  @impl true
  def send_response(%{content: content, external_ref: channel_id} = message, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(content, channel_id, token, deliver, Map.get(message, :metadata) || %{})
  end

  @impl true
  def normalize_inbound(event) do
    case handle_event(event, %{}) do
      {:messages, messages, _state} -> {:ok, messages}
      other -> {:error, {:unexpected_adapter_response, other}}
    end
  end

  @impl true
  def deliver(message, state) do
    case send_response(message, state) do
      :ok -> {:ok, %{channel: "slack"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def health(state) do
    %{
      channel: "slack",
      configured: true,
      supports_threads: true,
      supports_rich_formatting: true,
      supports_attachments: true,
      supports_streaming: false,
      signing_secret: present?(state[:signing_secret])
    }
  end

  @impl true
  def sync_status(state) do
    {:ok,
     %{
       signing_secret: present?(state.signing_secret)
     }}
  end

  @impl true
  def capabilities do
    %{
      channel: "slack",
      inbound: [:message, :thread_reply],
      outbound: [:text],
      threads: true,
      attachments: true,
      rich_formatting: true,
      streaming: false
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: channel_id} = message, _state) do
    %{
      text: content,
      channel: channel_id,
      thread_ts: get_in(message, [:metadata, "thread_ts"])
    }
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

  defp do_send_response(content, channel_id, _token, deliver, metadata) when is_function(deliver, 1) do
    case deliver.(%{content: content, external_ref: channel_id, metadata: metadata}) do
      :ok -> {:ok, %{channel: "slack"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, Map.put_new(metadata, :channel, "slack")}
      other -> other
    end
  end

  defp do_send_response(content, channel_id, token, _deliver, metadata) do
    body =
      %{channel: channel_id, text: content}
      |> maybe_add_thread_ts(metadata["thread_ts"])

    case Req.post(
           url: "#{@slack_api}/chat.postMessage",
           headers: [{"authorization", "Bearer #{token}"}],
           json: body
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

  defp present?(value), do: is_binary(value) and value != ""

  defp message_content(event, attachments) do
    event["text"] || attachment_summary(attachments)
  end

  defp attachment_summary([]), do: nil

  defp attachment_summary(attachments) do
    kinds =
      attachments
      |> Enum.map(&(&1["content_type"] || &1["kind"] || "attachment"))
      |> Enum.uniq()
      |> Enum.join(", ")

    "[Slack attachments: #{kinds}]"
  end

  defp extract_attachments(%{"files" => files}) when is_list(files) do
    Enum.map(files, fn file ->
      %{
        "kind" => "file",
        "id" => file["id"],
        "file_name" => file["name"],
        "content_type" => file["mimetype"],
        "url" => file["url_private"],
        "size" => file["size"]
      }
    end)
  end

  defp extract_attachments(_event), do: []

  defp maybe_add_thread_ts(body, nil), do: body
  defp maybe_add_thread_ts(body, ""), do: body
  defp maybe_add_thread_ts(body, thread_ts), do: Map.put(body, :thread_ts, thread_ts)
end
