defmodule HydraX.Gateway.Adapters.Telegram do
  @moduledoc """
  Telegram adapter skeleton with request/response mapping.
  """

  @behaviour HydraX.Gateway.Adapter
  @telegram_message_limit 4_096

  @impl true
  def connect(%{"bot_token" => token} = config) when is_binary(token) and token != "" do
    {:ok,
     %{
       bot_token: token,
       bot_username: config["bot_username"],
       webhook_secret: config["webhook_secret"],
       deliver: config["deliver"]
     }}
  end

  def connect(_config), do: {:error, :missing_bot_token}

  @impl true
  def handle_event(%{"message" => %{"chat" => %{"id" => chat_id}} = message} = event, state) do
    attachments = extract_attachments(message)
    content = message_content(message, attachments)

    message = %{
      channel: "telegram",
      external_ref: to_string(chat_id),
      content: content,
      metadata: %{
        raw: event,
        attachments: attachments,
        reply_to_message_id: message["message_id"]
      }
    }

    {:messages, [message], state}
  end

  def handle_event(_event, state), do: {:messages, [], state}

  @impl true
  def send_response(%{content: content, external_ref: external_ref} = message, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(content, external_ref, token, deliver, Map.get(message, :metadata) || %{})
  end

  def send_response(%{text: content, chat_id: external_ref} = message, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(
      content,
      external_ref,
      token,
      deliver,
      %{"reply_to_message_id" => Map.get(message, :reply_to_message_id)}
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
      :ok -> {:ok, %{channel: "telegram"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def health(state) do
    %{
      channel: "telegram",
      configured: true,
      supports_threads: false,
      supports_rich_formatting: false,
      supports_attachments: true,
      supports_streaming: false,
      webhook_secret: present?(state[:webhook_secret])
    }
  end

  @impl true
  def sync_status(state) do
    case webhook_info(state.bot_token) do
      {:ok, info} ->
        {:ok,
         %{
           webhook_url: info["url"],
           pending_update_count: info["pending_update_count"] || 0,
           last_error: info["last_error_message"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def capabilities do
    %{
      channel: "telegram",
      inbound: [:message, :caption, :document, :photo, :audio, :voice, :video],
      outbound: [:text],
      threads: false,
      attachments: true,
      rich_formatting: false,
      streaming: false
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: external_ref} = message, _state) do
    chunks = chunk_message(content, @telegram_message_limit)

    %{
      text: List.first(chunks) || "",
      chat_id: external_ref,
      reply_to_message_id: get_in(message, [:metadata, "reply_to_message_id"]),
      chunk_count: length(chunks),
      truncated: length(chunks) > 1
    }
  end

  def register_webhook(bot_token, url, secret, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Req.post/1)

    body =
      %{url: url, drop_pending_updates: false}
      |> maybe_put_secret(secret)

    case request_fn.(
           url: "https://api.telegram.org/bot#{bot_token}/setWebhook",
           json: body
         ) do
      {:ok, %{status: 200, body: %{"ok" => true}}} -> :ok
      {:ok, %{status: 200, body: %{"ok" => false} = body}} -> {:error, {:telegram_error, body}}
      {:ok, response} -> {:error, {:telegram_error, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def webhook_info(bot_token, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Req.get/1)

    case request_fn.(url: "https://api.telegram.org/bot#{bot_token}/getWebhookInfo") do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => result}}} -> {:ok, result}
      {:ok, %{status: 200, body: %{"ok" => false} = body}} -> {:error, {:telegram_error, body}}
      {:ok, response} -> {:error, {:telegram_error, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_webhook(bot_token, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Req.post/1)

    case request_fn.(url: "https://api.telegram.org/bot#{bot_token}/deleteWebhook", json: %{}) do
      {:ok, %{status: 200, body: %{"ok" => true}}} -> :ok
      {:ok, %{status: 200, body: %{"ok" => false} = body}} -> {:error, {:telegram_error, body}}
      {:ok, response} -> {:error, {:telegram_error, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_send_response(content, external_ref, _token, deliver, metadata) when is_function(deliver, 1) do
    content
    |> chunk_message(@telegram_message_limit)
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, %{channel: "telegram", chunk_count: 0, provider_message_ids: []}},
      fn {chunk, index}, {:ok, acc} ->
        payload = %{
          text: chunk,
          chat_id: external_ref,
          reply_to_message_id: if(index == 0, do: metadata["reply_to_message_id"])
        }

        case deliver.(payload) do
          :ok ->
            {:cont, {:ok, %{acc | chunk_count: acc.chunk_count + 1}}}

          {:ok, metadata} when is_map(metadata) ->
            provider_message_id = metadata[:provider_message_id] || metadata["provider_message_id"]

            updated =
              acc
              |> Map.put(:chunk_count, acc.chunk_count + 1)
              |> Map.put(:provider_message_id, provider_message_id || acc[:provider_message_id])
              |> Map.update!(:provider_message_ids, fn ids ->
                if provider_message_id, do: ids ++ [provider_message_id], else: ids
              end)

            {:cont, {:ok, updated}}

          other ->
            {:halt, other}
        end
      end
    )
  end

  defp do_send_response(content, external_ref, token, _deliver, metadata) do
    content
    |> chunk_message(@telegram_message_limit)
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, %{channel: "telegram", status: 200, chunk_count: 0, provider_message_ids: []}},
      fn {chunk, index}, {:ok, acc} ->
        form =
          [chat_id: external_ref, text: chunk]
          |> maybe_add_reply_to(if(index == 0, do: metadata["reply_to_message_id"]))

        case Req.post(
               url: "https://api.telegram.org/bot#{token}/sendMessage",
               form: form
             ) do
          {:ok, %{status: 200, body: %{"ok" => true, "result" => result}}} ->
            provider_message_id = Map.get(result, "message_id")

            updated =
              acc
              |> Map.put(:chunk_count, acc.chunk_count + 1)
              |> Map.put(:provider_message_id, provider_message_id || acc[:provider_message_id])
              |> Map.update!(:provider_message_ids, fn ids ->
                if provider_message_id, do: ids ++ [provider_message_id], else: ids
              end)

            {:cont, {:ok, updated}}

          {:ok, %{status: 200}} ->
            {:cont, {:ok, %{acc | chunk_count: acc.chunk_count + 1}}}

          {:ok, response} ->
            {:halt, {:error, {:telegram_error, response.status}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
  end

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

  defp maybe_put_secret(body, nil), do: body
  defp maybe_put_secret(body, ""), do: body
  defp maybe_put_secret(body, secret), do: Map.put(body, :secret_token, secret)
  defp maybe_add_reply_to(form, nil), do: form
  defp maybe_add_reply_to(form, ""), do: form
  defp maybe_add_reply_to(form, reply_to), do: Keyword.put(form, :reply_to_message_id, reply_to)

  defp message_content(message, attachments) do
    message["text"] ||
      message["caption"] ||
      attachment_summary(attachments)
  end

  defp attachment_summary([]), do: "[Telegram attachment]"

  defp attachment_summary(attachments) do
    kinds =
      attachments
      |> Enum.map(& &1["kind"])
      |> Enum.uniq()
      |> Enum.join(", ")

    "[Telegram attachments: #{kinds}]"
  end

  defp extract_attachments(message) do
    []
    |> maybe_add_photo(message["photo"])
    |> maybe_add_document(message["document"])
    |> maybe_add_audio("audio", message["audio"])
    |> maybe_add_audio("voice", message["voice"])
    |> maybe_add_video(message["video"])
  end

  defp maybe_add_photo(attachments, photos) when is_list(photos) and photos != [] do
    photo = List.last(photos)

    attachments ++
      [
        %{
          "kind" => "photo",
          "file_id" => photo["file_id"],
          "download_ref" => "telegram:#{photo["file_id"]}",
          "file_unique_id" => photo["file_unique_id"],
          "width" => photo["width"],
          "height" => photo["height"],
          "file_size" => photo["file_size"]
        }
      ]
  end

  defp maybe_add_photo(attachments, _photos), do: attachments

  defp maybe_add_document(attachments, %{} = document) do
    attachments ++
      [
        %{
          "kind" => "document",
          "file_id" => document["file_id"],
          "download_ref" => "telegram:#{document["file_id"]}",
          "file_unique_id" => document["file_unique_id"],
          "file_name" => document["file_name"],
          "content_type" => document["mime_type"],
          "mime_type" => document["mime_type"],
          "file_size" => document["file_size"]
        }
      ]
  end

  defp maybe_add_document(attachments, _document), do: attachments

  defp maybe_add_audio(attachments, kind, %{} = audio) do
    attachments ++
      [
        %{
          "kind" => kind,
          "file_id" => audio["file_id"],
          "download_ref" => "telegram:#{audio["file_id"]}",
          "file_unique_id" => audio["file_unique_id"],
          "content_type" => audio["mime_type"],
          "mime_type" => audio["mime_type"],
          "duration" => audio["duration"],
          "file_size" => audio["file_size"]
        }
      ]
  end

  defp maybe_add_audio(attachments, _kind, _audio), do: attachments

  defp maybe_add_video(attachments, %{} = video) do
    attachments ++
      [
        %{
          "kind" => "video",
          "file_id" => video["file_id"],
          "download_ref" => "telegram:#{video["file_id"]}",
          "file_unique_id" => video["file_unique_id"],
          "width" => video["width"],
          "height" => video["height"],
          "duration" => video["duration"],
          "content_type" => video["mime_type"],
          "mime_type" => video["mime_type"],
          "file_size" => video["file_size"]
        }
      ]
  end

  defp maybe_add_video(attachments, _video), do: attachments

  defp present?(value), do: is_binary(value) and value != ""
end
