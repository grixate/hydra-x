defmodule HydraX.Gateway.Adapters.Slack do
  @moduledoc """
  Slack adapter implementing the Gateway.Adapter behaviour.

  Handles Slack Events API payloads and delivers responses via
  the Slack Web API (chat.postMessage).
  """

  @behaviour HydraX.Gateway.Adapter
  @slack_message_limit 3_500

  @slack_api "https://slack.com/api"

  @impl true
  def connect(%{"bot_token" => token} = config) when is_binary(token) and token != "" do
    {:ok,
     %{
       bot_token: token,
       signing_secret: config["signing_secret"],
       deliver: config["deliver"],
       deliver_stream: config["deliver_stream"]
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

  def send_response(%{text: content, channel: channel_id} = message, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(
      content,
      channel_id,
      token,
      deliver,
      %{"thread_ts" => Map.get(message, :thread_ts)}
    )
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
  def deliver_stream(%{content: content, external_ref: channel_id} = message, %{
        bot_token: token,
        deliver_stream: deliver_stream
      }) do
    metadata = Map.get(message, :metadata) || %{}
    chunk_count = Map.get(message, :chunk_count, 0)

    do_deliver_stream(content, channel_id, token, deliver_stream, metadata, chunk_count)
  end

  @impl true
  def health(state) do
    %{
      channel: "slack",
      configured: true,
      supports_threads: true,
      supports_rich_formatting: true,
      supports_attachments: true,
      supports_streaming: true,
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
      outbound: [:text, :chunked_text],
      threads: true,
      attachments: true,
      rich_formatting: true,
      streaming: true,
      stream_transport: "slack_chat_update"
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: channel_id} = message, _state) do
    chunks = chunk_message(content, @slack_message_limit)

    %{
      text: List.first(chunks) || "",
      channel: channel_id,
      thread_ts: get_in(message, [:metadata, "thread_ts"]),
      chunk_count: length(chunks),
      truncated: length(chunks) > 1
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

  defp do_send_response(content, channel_id, _token, deliver, metadata)
       when is_function(deliver, 1) do
    case metadata["stream_message_id"] do
      nil ->
        content
        |> chunk_message(@slack_message_limit)
        |> Enum.reduce_while(
          {:ok, %{channel: "slack", chunk_count: 0, provider_message_ids: []}},
          fn chunk, {:ok, acc} ->
            payload = %{
              text: chunk,
              channel: channel_id,
              thread_ts: metadata["thread_ts"]
            }

            case deliver.(payload) do
              :ok ->
                {:cont, {:ok, %{acc | chunk_count: acc.chunk_count + 1}}}

              {:ok, metadata} when is_map(metadata) ->
                provider_message_id =
                  metadata[:provider_message_id] || metadata["provider_message_id"]

                updated =
                  acc
                  |> Map.put(:chunk_count, acc.chunk_count + 1)
                  |> Map.put(
                    :provider_message_id,
                    provider_message_id || acc[:provider_message_id]
                  )
                  |> Map.update!(:provider_message_ids, fn ids ->
                    if provider_message_id, do: ids ++ [provider_message_id], else: ids
                  end)

                {:cont, {:ok, updated}}

              other ->
                {:halt, other}
            end
          end
        )

      stream_message_id ->
        payload = %{
          text: truncate_stream_text(content),
          channel: channel_id,
          thread_ts: metadata["thread_ts"],
          stream_message_id: stream_message_id
        }

        case deliver.(payload) do
          :ok ->
            {:ok,
             %{
               channel: "slack",
               chunk_count: 1,
               provider_message_id: stream_message_id,
               provider_message_ids: [stream_message_id]
             }}

          {:ok, response_metadata} when is_map(response_metadata) ->
            provider_message_id =
              response_metadata[:provider_message_id] ||
                response_metadata["provider_message_id"] ||
                stream_message_id

            {:ok,
             %{
               channel: "slack",
               chunk_count: 1,
               provider_message_id: provider_message_id,
               provider_message_ids: [provider_message_id]
             }}

          other ->
            other
        end
    end
  end

  defp do_send_response(content, channel_id, token, _deliver, metadata) do
    case metadata["stream_message_id"] do
      nil ->
        content
        |> chunk_message(@slack_message_limit)
        |> Enum.reduce_while(
          {:ok, %{channel: "slack", chunk_count: 0, provider_message_ids: []}},
          fn chunk, {:ok, acc} ->
            body =
              %{channel: channel_id, text: chunk}
              |> maybe_add_thread_ts(metadata["thread_ts"])

            case Req.post(
                   url: "#{@slack_api}/chat.postMessage",
                   headers: [{"authorization", "Bearer #{token}"}],
                   json: body
                 ) do
              {:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}} ->
                updated =
                  acc
                  |> Map.put(:chunk_count, acc.chunk_count + 1)
                  |> Map.put(:provider_message_id, ts || acc[:provider_message_id])
                  |> Map.update!(:provider_message_ids, fn ids ->
                    if ts, do: ids ++ [ts], else: ids
                  end)

                {:cont, {:ok, updated}}

              {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
                {:halt, {:error, {:slack_error, error}}}

              {:ok, %{status: status}} ->
                {:halt, {:error, {:slack_error, status}}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end
        )

      stream_message_id ->
        case Req.post(
               url: "#{@slack_api}/chat.update",
               headers: [{"authorization", "Bearer #{token}"}],
               json: %{
                 channel: channel_id,
                 ts: stream_message_id,
                 text: truncate_stream_text(content)
               }
             ) do
          {:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}} ->
            {:ok,
             %{
               channel: "slack",
               chunk_count: 1,
               provider_message_id: ts || stream_message_id,
               provider_message_ids: [ts || stream_message_id]
             }}

          {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
            {:error, {:slack_error, error}}

          {:ok, %{status: status}} ->
            {:error, {:slack_error, status}}

          {:error, reason} ->
            {:error, reason}
        end
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
        "download_ref" => file["url_private"],
        "source_url" => file["url_private"],
        "url" => file["url_private"],
        "size" => file["size"]
      }
    end)
  end

  defp extract_attachments(_event), do: []

  defp maybe_add_thread_ts(body, nil), do: body
  defp maybe_add_thread_ts(body, ""), do: body
  defp maybe_add_thread_ts(body, thread_ts), do: Map.put(body, :thread_ts, thread_ts)

  defp chunk_message(text, max_length) do
    if String.length(text) <= max_length do
      [text]
    else
      text
      |> String.codepoints()
      |> Enum.chunk_every(max_length)
      |> Enum.map(&Enum.join/1)
    end
  end

  defp do_deliver_stream(content, channel_id, _token, deliver_stream, metadata, chunk_count)
       when is_function(deliver_stream, 1) do
    payload = %{
      text: truncate_stream_text(content),
      channel: channel_id,
      thread_ts: metadata["thread_ts"],
      stream_message_id: metadata["stream_message_id"],
      chunk_count: chunk_count,
      stream: true
    }

    case deliver_stream.(payload) do
      :ok ->
        {:ok, %{channel: "slack", streaming: true, transport: "slack_chat_update"}}

      {:ok, response_metadata} when is_map(response_metadata) ->
        {:ok,
         %{
           channel: "slack",
           streaming: true,
           transport: "slack_chat_update",
           provider_message_id:
             response_metadata[:provider_message_id] || response_metadata["provider_message_id"]
         }}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_stream_response, other}}
    end
  end

  defp do_deliver_stream(content, channel_id, token, _deliver_stream, metadata, _chunk_count) do
    text = truncate_stream_text(content)

    case metadata["stream_message_id"] do
      nil ->
        body =
          %{channel: channel_id, text: text}
          |> maybe_add_thread_ts(metadata["thread_ts"])

        case Req.post(
               url: "#{@slack_api}/chat.postMessage",
               headers: [{"authorization", "Bearer #{token}"}],
               json: body
             ) do
          {:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}} ->
            {:ok,
             %{
               channel: "slack",
               streaming: true,
               transport: "slack_chat_update",
               provider_message_id: ts
             }}

          {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
            {:error, {:slack_error, error}}

          {:ok, %{status: status}} ->
            {:error, {:slack_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      stream_message_id ->
        case Req.post(
               url: "#{@slack_api}/chat.update",
               headers: [{"authorization", "Bearer #{token}"}],
               json: %{channel: channel_id, ts: stream_message_id, text: text}
             ) do
          {:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}} ->
            {:ok,
             %{
               channel: "slack",
               streaming: true,
               transport: "slack_chat_update",
               provider_message_id: ts || stream_message_id
             }}

          {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
            {:error, {:slack_error, error}}

          {:ok, %{status: status}} ->
            {:error, {:slack_error, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp truncate_stream_text(text) when is_binary(text) do
    String.slice(text, 0, @slack_message_limit)
  end

  defp truncate_stream_text(_text), do: ""
end
