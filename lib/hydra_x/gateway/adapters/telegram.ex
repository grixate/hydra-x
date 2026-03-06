defmodule HydraX.Gateway.Adapters.Telegram do
  @moduledoc """
  Telegram adapter skeleton with request/response mapping.
  """

  @behaviour HydraX.Gateway.Adapter

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
      metadata: %{raw: event, attachments: attachments}
    }

    {:messages, [message], state}
  end

  def handle_event(_event, state), do: {:messages, [], state}

  @impl true
  def send_response(%{content: content, external_ref: external_ref}, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(content, external_ref, token, deliver)
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

  defp do_send_response(content, external_ref, _token, deliver) when is_function(deliver, 1) do
    case deliver.(%{content: content, external_ref: external_ref}) do
      :ok -> {:ok, %{channel: "telegram"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, Map.put_new(metadata, :channel, "telegram")}
      other -> other
    end
  end

  defp do_send_response(content, external_ref, token, _deliver) do
    case Req.post(
           url: "https://api.telegram.org/bot#{token}/sendMessage",
           form: [chat_id: external_ref, text: content]
         ) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok,
         %{
           channel: "telegram",
           provider_message_id: Map.get(result, "message_id"),
           status: 200
         }}

      {:ok, %{status: 200}} ->
        {:ok, %{channel: "telegram", status: 200}}

      {:ok, response} ->
        {:error, {:telegram_error, response.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_secret(body, nil), do: body
  defp maybe_put_secret(body, ""), do: body
  defp maybe_put_secret(body, secret), do: Map.put(body, :secret_token, secret)

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
          "file_unique_id" => document["file_unique_id"],
          "file_name" => document["file_name"],
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
          "file_unique_id" => audio["file_unique_id"],
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
          "file_unique_id" => video["file_unique_id"],
          "width" => video["width"],
          "height" => video["height"],
          "duration" => video["duration"],
          "mime_type" => video["mime_type"],
          "file_size" => video["file_size"]
        }
      ]
  end

  defp maybe_add_video(attachments, _video), do: attachments
end
