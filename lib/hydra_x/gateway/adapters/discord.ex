defmodule HydraX.Gateway.Adapters.Discord do
  @moduledoc """
  Discord adapter implementing the Gateway.Adapter behaviour.

  Handles Discord webhook interaction payloads and delivers responses
  via the Discord REST API.
  """

  @behaviour HydraX.Gateway.Adapter

  @discord_api "https://discord.com/api/v10"

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
        %{"d" => %{"content" => content, "channel_id" => channel_id}} = event,
        state
      )
      when is_binary(content) and content != "" do
    # Gateway MESSAGE_CREATE event
    message = %{
      channel: "discord",
      external_ref: channel_id,
      content: content,
      metadata: %{
        raw: event,
        guild_id: get_in(event, ["d", "guild_id"]),
        user: extract_gateway_user(event)
      }
    }

    {:messages, [message], state}
  end

  def handle_event(_event, state), do: {:messages, [], state}

  @impl true
  def send_response(%{content: content, external_ref: channel_id}, %{
        bot_token: token,
        deliver: deliver
      }) do
    do_send_response(content, channel_id, token, deliver)
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
      supports_attachments: false,
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
      attachments: false,
      rich_formatting: true,
      streaming: false
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: channel_id}, _state) do
    %{content: content, channel_id: channel_id}
  end

  # -- Private --

  defp do_send_response(content, channel_id, _token, deliver) when is_function(deliver, 1) do
    case deliver.(%{content: content, external_ref: channel_id}) do
      :ok -> {:ok, %{channel: "discord"}}
      {:ok, metadata} when is_map(metadata) -> {:ok, Map.put_new(metadata, :channel, "discord")}
      other -> other
    end
  end

  defp do_send_response(content, channel_id, token, _deliver) do
    # Discord message limit is 2000 chars — split if needed
    chunks = chunk_message(content, 2000)

    Enum.reduce_while(chunks, {:ok, %{channel: "discord"}}, fn chunk, _acc ->
      case Req.post(
             url: "#{@discord_api}/channels/#{channel_id}/messages",
             headers: [{"authorization", "Bot #{token}"}],
             json: %{content: chunk}
           ) do
        {:ok, %{status: 200, body: %{"id" => message_id}}} ->
          {:cont, {:ok, %{channel: "discord", provider_message_id: message_id}}}

        {:ok, %{status: status}} ->
          {:halt, {:error, {:discord_error, status}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
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

  defp present?(value), do: is_binary(value) and value != ""
end
