defmodule HydraX.Gateway do
  @moduledoc """
  Routes inbound adapter messages into agent conversations.
  """

  alias HydraX.Gateway.Adapters.{Discord, Slack, Telegram, Webchat}
  alias HydraX.Runtime
  alias HydraX.Runtime.Conversation
  alias HydraX.Safety
  alias HydraX.Telemetry

  def channel_capabilities do
    %{
      "telegram" => Telegram.capabilities(),
      "discord" => Discord.capabilities(),
      "slack" => Slack.capabilities(),
      "webchat" => Webchat.capabilities()
    }
  end

  def dispatch_telegram_update(update, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_telegram_config(),
      Telegram,
      adapter_config(Runtime.enabled_telegram_config(), opts),
      update,
      :telegram_not_configured
    )
  end

  def dispatch_discord_update(event, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_discord_config(),
      Discord,
      discord_adapter_config(Runtime.enabled_discord_config(), opts),
      event,
      :discord_not_configured
    )
  end

  def dispatch_slack_update(event, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_slack_config(),
      Slack,
      slack_adapter_config(Runtime.enabled_slack_config(), opts),
      event,
      :slack_not_configured
    )
  end

  def dispatch_webchat_message(payload, opts \\ %{}) do
    dispatch_channel_update(
      Runtime.enabled_webchat_config(),
      Webchat,
      webchat_adapter_config(Runtime.enabled_webchat_config(), opts),
      payload,
      :webchat_not_configured
    )
  end

  def retry_conversation_delivery(%Conversation{} = conversation, opts \\ %{}) do
    conversation = Runtime.get_conversation!(conversation.id)

    with delivery when is_map(delivery) <- last_delivery(conversation),
         {:ok, adapter_mod, _config, config_map} <- retry_adapter(delivery, opts),
         {:ok, state} <- adapter_mod.connect(config_map),
         %{content: content} <- latest_assistant_turn(conversation) do
      external_ref = Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)

      result =
        adapter_deliver(adapter_mod, %{content: content, external_ref: external_ref}, state)

      record_delivery_result(
        conversation.agent_id,
        conversation,
        delivery_message(delivery),
        result,
        retry: true
      )
    else
      nil -> {:error, :missing_delivery}
      :no_assistant_turn -> {:error, :no_assistant_turn}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :channel_not_configured}
    end
  end

  @max_retries 3
  @retry_backoffs [5_000, 30_000, 120_000]

  defp route_message(message, state, config, adapter_mod) do
    agent = config.default_agent || Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    conversation =
      Runtime.find_conversation(agent.id, message.channel, message.external_ref) ||
        start_channel_conversation(agent, message)

    response =
      HydraX.Agent.Channel.submit(
        agent,
        conversation,
        message.content,
        Map.merge(message.metadata || %{}, %{source: message.channel})
      )

    delivery_result =
      adapter_deliver(
        adapter_mod,
        %{content: response, external_ref: message.external_ref},
        state
      )

    record_delivery_result(agent.id, conversation, message, delivery_result)

    case delivery_result do
      {:error, _reason} ->
        schedule_retry(agent.id, conversation.id, message, adapter_mod, config, 0)

      _ ->
        :ok
    end
  end

  defp schedule_retry(_agent_id, _conversation_id, _message, _adapter_mod, _config, attempt)
       when attempt >= @max_retries,
       do: :ok

  defp schedule_retry(agent_id, conversation_id, message, adapter_mod, config, attempt) do
    delay = Enum.at(@retry_backoffs, attempt, List.last(@retry_backoffs))

    Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
      Process.sleep(delay)
      execute_retry(agent_id, conversation_id, message, adapter_mod, config, attempt)
    end)
  end

  defp execute_retry(agent_id, conversation_id, message, adapter_mod, config, attempt) do
    conversation = Runtime.get_conversation!(conversation_id)

    with {:ok, state} <- adapter_mod.connect(retry_adapter_config(adapter_mod, config)),
         %{content: content} <- latest_assistant_turn(conversation) do
      result =
        adapter_deliver(
          adapter_mod,
          %{content: content, external_ref: message.external_ref},
          state
        )

      record_delivery_result(agent_id, conversation, message, result, retry: true)

      case result do
        {:error, _reason} ->
          next_attempt = attempt + 1

          if next_attempt >= @max_retries do
            mark_dead_letter(agent_id, conversation, message, adapter_mod)
          else
            schedule_retry(agent_id, conversation_id, message, adapter_mod, config, next_attempt)
          end

        _ ->
          :ok
      end
    end
  rescue
    _error -> :ok
  end

  defp mark_dead_letter(agent_id, conversation, message, adapter_mod) do
    Safety.log_event(%{
      agent_id: agent_id,
      conversation_id: conversation.id,
      category: "gateway",
      level: "error",
      message:
        "#{adapter_channel(adapter_mod)} delivery dead-lettered after #{@max_retries} retries",
      metadata: %{
        channel: message.channel,
        external_ref: message.external_ref
      }
    })

    delivery =
      conversation
      |> delivery_payload(message, retry: true)
      |> Map.put("status", "dead_letter")
      |> Map.put("dead_lettered_at", DateTime.utc_now())

    Runtime.update_conversation_metadata(conversation, %{"last_delivery" => delivery})
  end

  defp route_channel_message(message, state, config, adapter_mod) do
    route_message(message, state, config, adapter_mod)
  end

  defp start_channel_conversation(agent, message) do
    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: message.channel,
        external_ref: message.external_ref,
        title: "#{String.capitalize(message.channel)} #{message.external_ref}",
        metadata: %{source: message.channel}
      })

    conversation
  end

  defp adapter_config(config, opts) do
    %{
      "bot_token" => config && config.bot_token,
      "bot_username" => config && config.bot_username,
      "webhook_secret" => config && config.webhook_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :telegram_deliver)
    }
  end

  defp discord_adapter_config(config, opts) do
    %{
      "bot_token" => config && config.bot_token,
      "application_id" => config && config.application_id,
      "webhook_secret" => config && config.webhook_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :discord_deliver)
    }
  end

  defp slack_adapter_config(config, opts) do
    %{
      "bot_token" => config && config.bot_token,
      "signing_secret" => config && config.signing_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :slack_deliver)
    }
  end

  defp webchat_adapter_config(config, _opts) do
    %{
      "enabled" => config && config.enabled,
      "title" => config && config.title,
      "subtitle" => config && config.subtitle,
      "welcome_prompt" => config && config.welcome_prompt,
      "composer_placeholder" => config && config.composer_placeholder
    }
  end

  defp record_delivery_result(agent_id, conversation, message, result, opts \\ [])

  defp record_delivery_result(_agent_id, conversation, message, {:ok, metadata}, opts)
       when is_map(metadata) do
    Telemetry.gateway_delivery(message.channel, :ok)

    delivery = delivery_payload(conversation, message, opts)

    Runtime.update_conversation_metadata(conversation, %{
      "last_delivery" =>
        delivery
        |> Map.put("status", "delivered")
        |> Map.put("delivered_at", DateTime.utc_now())
        |> Map.put("metadata", stringify_keys(metadata))
        |> Map.delete("reason")
    })
  end

  defp record_delivery_result(agent_id, conversation, message, :ok, opts) do
    record_delivery_result(agent_id, conversation, message, {:ok, %{}}, opts)
  end

  defp record_delivery_result(agent_id, conversation, message, {:error, reason}, opts) do
    reason_text = inspect(reason)
    Telemetry.gateway_delivery(message.channel, :error, %{reason: reason_text})

    Safety.log_event(%{
      agent_id: agent_id,
      conversation_id: conversation.id,
      category: "gateway",
      level: "error",
      message: "#{String.capitalize(message.channel)} delivery failed",
      metadata: %{
        channel: message.channel,
        external_ref: message.external_ref,
        reason: reason_text
      }
    })

    delivery =
      conversation
      |> delivery_payload(message, opts)
      |> Map.put("status", "failed")
      |> Map.put("attempted_at", DateTime.utc_now())
      |> Map.put("reason", reason_text)

    Runtime.update_conversation_metadata(conversation, %{"last_delivery" => delivery})
  end

  defp stringify_keys(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery]
  end

  defp latest_assistant_turn(conversation) do
    conversation.turns
    |> Enum.reverse()
    |> Enum.find(:no_assistant_turn, &(&1.role == "assistant"))
  end

  defp delivery_message(delivery) do
    %{
      channel: Map.get(delivery, "channel") || Map.get(delivery, :channel) || "telegram",
      external_ref: Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)
    }
  end

  defp validate_delivery(delivery) do
    channel = Map.get(delivery, "channel") || Map.get(delivery, :channel)
    external_ref = Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)

    cond do
      channel not in ~w(telegram discord slack webchat) ->
        {:error, {:unsupported_channel, channel}}

      not (is_binary(external_ref) and external_ref != "") ->
        {:error, :missing_external_ref}

      true ->
        :ok
    end
  end

  defp delivery_payload(conversation, message, opts) do
    retries =
      case last_delivery(conversation) do
        %{"retry_count" => count} when is_integer(count) -> count
        %{retry_count: count} when is_integer(count) -> count
        _ -> 0
      end

    retry_count = if Keyword.get(opts, :retry, false), do: retries + 1, else: retries

    %{
      "channel" => message.channel,
      "external_ref" => message.external_ref,
      "retry_count" => retry_count
    }
  end

  defp dispatch_channel_update(nil, _adapter_mod, _adapter_config, _event, error),
    do: {:error, error}

  defp dispatch_channel_update(config, adapter_mod, adapter_config, event, _error) do
    with {:ok, state} <- adapter_mod.connect(adapter_config),
         {:ok, messages} <- adapter_normalize_inbound(adapter_mod, event, state) do
      Enum.each(messages, &route_channel_message(&1, state, config, adapter_mod))
      :ok
    end
  end

  defp adapter_normalize_inbound(adapter_mod, event, state) do
    cond do
      function_exported?(adapter_mod, :normalize_inbound, 1) ->
        adapter_mod.normalize_inbound(event)

      true ->
        case adapter_mod.handle_event(event, state) do
          {:messages, messages, _state} -> {:ok, messages}
          other -> {:error, {:unexpected_adapter_response, other}}
        end
    end
  end

  defp adapter_deliver(adapter_mod, payload, state) do
    cond do
      function_exported?(adapter_mod, :deliver, 2) ->
        adapter_mod.deliver(payload, state)

      true ->
        adapter_mod.send_response(payload, state)
    end
  end

  defp retry_adapter(delivery, opts) do
    with :ok <- validate_delivery(delivery) do
      channel = Map.get(delivery, "channel") || Map.get(delivery, :channel)

      case channel do
        "telegram" ->
          config = Runtime.enabled_telegram_config()

          maybe_retry_adapter(
            Telegram,
            config,
            adapter_config(config, opts),
            :telegram_not_configured
          )

        "discord" ->
          config = Runtime.enabled_discord_config()

          maybe_retry_adapter(
            Discord,
            config,
            discord_adapter_config(config, opts),
            :discord_not_configured
          )

        "slack" ->
          config = Runtime.enabled_slack_config()

          maybe_retry_adapter(
            Slack,
            config,
            slack_adapter_config(config, opts),
            :slack_not_configured
          )

        "webchat" ->
          config = Runtime.enabled_webchat_config()

          maybe_retry_adapter(
            Webchat,
            config,
            webchat_adapter_config(config, opts),
            :webchat_not_configured
          )
      end
    end
  end

  defp maybe_retry_adapter(_adapter_mod, nil, _config_map, error), do: {:error, error}

  defp maybe_retry_adapter(adapter_mod, config, config_map, _error),
    do: {:ok, adapter_mod, config, config_map}

  defp retry_adapter_config(Telegram, config), do: adapter_config(config, %{})
  defp retry_adapter_config(Discord, config), do: discord_adapter_config(config, %{})
  defp retry_adapter_config(Slack, config), do: slack_adapter_config(config, %{})
  defp retry_adapter_config(Webchat, config), do: webchat_adapter_config(config, %{})

  defp adapter_channel(Telegram), do: "Telegram"
  defp adapter_channel(Discord), do: "Discord"
  defp adapter_channel(Slack), do: "Slack"
  defp adapter_channel(Webchat), do: "Webchat"
end
