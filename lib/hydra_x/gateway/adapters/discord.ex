defmodule HydraX.Gateway.Adapters.Discord do
  @moduledoc """
  Discord adapter implementing the Gateway.Adapter behaviour.

  Handles Discord webhook interaction payloads and delivers responses
  via the Discord REST API.
  """

  @behaviour HydraX.Gateway.Adapter

  @discord_api "https://discord.com/api/v10"
  @discord_message_limit 2_000

  @impl true
  def connect(%{"bot_token" => token} = config) when is_binary(token) and token != "" do
    {:ok,
     %{
       bot_token: token,
       application_id: config["application_id"],
       webhook_secret: config["webhook_secret"],
       deliver: config["deliver"]
     }}
  end

  def connect(_config), do: {:error, :missing_bot_token}

  @impl true
  def handle_event(
        %{"type" => 1} = _interaction,
        state
      ) do
    # PING interaction — Discord sends this for verification
    {:messages, [], state}
  end

  def handle_event(
        %{
          "type" => 2,
          "data" => %{"name" => _command_name} = data,
          "channel_id" => channel_id
        } = event,
        state
      ) do
    # APPLICATION_COMMAND (slash command)
    content = extract_command_content(data)

    message = %{
      channel: "discord",
      external_ref: channel_id,
      content: content,
      metadata: %{
        raw: event,
        interaction_id: event["id"],
        interaction_token: event["token"],
        guild_id: event["guild_id"],
        user: extract_user(event)
      }
    }

    {:messages, [message], state}
  end

  def handle_event(
        %{"d" => %{"channel_id" => channel_id} = payload} = event,
        state
      )
      do
    # Gateway MESSAGE_CREATE event
    attachments = extract_attachments(payload)
    content = message_content(payload, attachments)

    if is_binary(content) and content != "" do
    message = %{
      channel: "discord",
      external_ref: channel_id,
      content: content,
      metadata: %{
        raw: event,
        guild_id: get_in(event, ["d", "guild_id"]),
        user: extract_gateway_user(event),
        reply_to_message_id: get_in(event, ["d", "id"]),
        source_message_id: get_in(event, ["d", "id"]),
        attachments: attachments
      }
    }

      {:messages, [message], state}
    else
      {:messages, [], state}
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

  def send_response(%{content: content, channel_id: channel_id} = message, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(
      content,
      channel_id,
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
      :ok -> {:ok, %{channel: "discord"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def health(state) do
    %{
      channel: "discord",
      configured: true,
      supports_threads: true,
      supports_rich_formatting: true,
      supports_attachments: true,
      supports_streaming: false,
      application_id: state[:application_id]
    }
  end

  @impl true
  def sync_status(state) do
    {:ok,
     %{
       application_id: state.application_id,
       webhook_secret: present?(state[:webhook_secret])
     }}
  end

  @impl true
  def capabilities do
    %{
      channel: "discord",
      inbound: [:message, :slash_command],
      outbound: [:text, :chunked_text],
      threads: true,
      attachments: true,
      rich_formatting: true,
      streaming: false
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: channel_id} = message, _state) do
    chunks = chunk_message(content, @discord_message_limit)

    %{
      content: List.first(chunks) || "",
      channel_id: channel_id,
      reply_to_message_id: get_in(message, [:metadata, "reply_to_message_id"]),
      chunk_count: length(chunks),
      truncated: length(chunks) > 1
    }
  end

  # -- Private --

  defp do_send_response(content, channel_id, _token, deliver, metadata) when is_function(deliver, 1) do
    content
    |> chunk_message(@discord_message_limit)
    |> Enum.reduce_while(
      {:ok, %{channel: "discord", chunk_count: 0, provider_message_ids: []}},
      fn chunk, {:ok, acc} ->
        payload = %{
          content: chunk,
          channel_id: channel_id,
          reply_to_message_id: metadata["reply_to_message_id"]
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

  defp do_send_response(content, channel_id, token, _deliver, metadata) do
    chunks = chunk_message(content, @discord_message_limit)

    Enum.reduce_while(
      chunks,
      {:ok, %{channel: "discord", chunk_count: 0, provider_message_ids: []}},
      fn chunk, {:ok, acc} ->
      body =
        %{content: chunk}
        |> maybe_add_message_reference(metadata["reply_to_message_id"])

      case Req.post(
             url: "#{@discord_api}/channels/#{channel_id}/messages",
             headers: [{"authorization", "Bot #{token}"}],
             json: body
           ) do
        {:ok, %{status: 200, body: %{"id" => message_id}}} ->
          updated =
            acc
            |> Map.put(:chunk_count, acc.chunk_count + 1)
            |> Map.put(:provider_message_id, message_id || acc[:provider_message_id])
            |> Map.update!(:provider_message_ids, fn ids ->
              if message_id, do: ids ++ [message_id], else: ids
            end)

          {:cont, {:ok, updated}}

        {:ok, %{status: status}} ->
          {:halt, {:error, {:discord_error, status}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
      end
    )
  end

  defp extract_command_content(%{"name" => name, "options" => options})
       when is_list(options) and options != [] do
    args =
      options
      |> Enum.map(fn opt -> "#{opt["name"]}: #{opt["value"]}" end)
      |> Enum.join(", ")

    "/#{name} #{args}"
  end

  defp extract_command_content(%{"name" => name}), do: "/#{name}"

  defp extract_user(%{"member" => %{"user" => user}}), do: user_info(user)
  defp extract_user(%{"user" => user}), do: user_info(user)
  defp extract_user(_event), do: nil

  defp extract_gateway_user(%{"d" => %{"author" => author}}), do: user_info(author)
  defp extract_gateway_user(_event), do: nil

  defp message_content(payload, attachments) do
    payload["content"] || attachment_summary(attachments)
  end

  defp attachment_summary([]), do: nil

  defp attachment_summary(attachments) do
    kinds =
      attachments
      |> Enum.map(&(&1["content_type"] || &1["kind"] || "attachment"))
      |> Enum.uniq()
      |> Enum.join(", ")

    "[Discord attachments: #{kinds}]"
  end

  defp extract_attachments(%{"attachments" => attachments}) when is_list(attachments) do
    Enum.map(attachments, fn attachment ->
      %{
        "kind" => "attachment",
        "id" => attachment["id"],
        "file_name" => attachment["filename"],
        "content_type" => attachment["content_type"],
        "download_ref" => attachment["url"],
        "source_url" => attachment["url"],
        "url" => attachment["url"],
        "proxy_url" => attachment["proxy_url"],
        "size" => attachment["size"]
      }
    end)
  end

  defp extract_attachments(_payload), do: []

  defp user_info(%{"id" => id} = user) do
    %{
      "id" => id,
      "username" => user["username"],
      "discriminator" => user["discriminator"]
    }
  end

  defp user_info(_), do: nil

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

  defp maybe_add_message_reference(body, nil), do: body
  defp maybe_add_message_reference(body, ""), do: body

  defp maybe_add_message_reference(body, message_id) do
    Map.put(body, :message_reference, %{message_id: message_id})
  end

  defp present?(value), do: is_binary(value) and value != ""
end
