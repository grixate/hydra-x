defmodule HydraX.Gateway do
  @moduledoc """
  Routes inbound adapter messages into agent conversations.
  """

  alias HydraX.Gateway.Adapters.Telegram
  alias HydraX.Runtime
  alias HydraX.Runtime.Conversation
  alias HydraX.Safety
  alias HydraX.Telemetry

  def dispatch_telegram_update(update, opts \\ %{}) do
    with config when not is_nil(config) <- Runtime.enabled_telegram_config(),
         {:ok, state} <- Telegram.connect(adapter_config(config, opts)),
         {:messages, messages, state} <- Telegram.handle_event(update, state) do
      Enum.each(messages, &route_message(&1, state, config))
      :ok
    else
      nil -> {:error, :telegram_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  def retry_conversation_delivery(%Conversation{} = conversation, opts \\ %{}) do
    conversation = Runtime.get_conversation!(conversation.id)

    with delivery when is_map(delivery) <- last_delivery(conversation),
         :ok <- validate_delivery(delivery),
         config when not is_nil(config) <- Runtime.enabled_telegram_config(),
         {:ok, state} <- Telegram.connect(adapter_config(config, opts)),
         %{content: content} <- latest_assistant_turn(conversation) do
      external_ref = Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)
      result = Telegram.send_response(%{content: content, external_ref: external_ref}, state)

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
      _ -> {:error, :telegram_not_configured}
    end
  end

  defp route_message(message, state, config) do
    agent = config.default_agent || Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    conversation =
      Runtime.find_conversation(agent.id, message.channel, message.external_ref) ||
        start_telegram_conversation(agent, message)

    response =
      HydraX.Agent.Channel.submit(
        agent,
        conversation,
        message.content,
        Map.merge(message.metadata || %{}, %{source: message.channel})
      )

    delivery_result =
      Telegram.send_response(%{content: response, external_ref: message.external_ref}, state)

    record_delivery_result(agent.id, conversation, message, delivery_result)
  end

  defp start_telegram_conversation(agent, message) do
    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: message.channel,
        external_ref: message.external_ref,
        title: "Telegram #{message.external_ref}",
        metadata: %{source: "telegram"}
      })

    conversation
  end

  defp adapter_config(config, opts) do
    %{
      "bot_token" => config.bot_token,
      "bot_username" => config.bot_username,
      "webhook_secret" => config.webhook_secret,
      "deliver" => Map.get(opts, :deliver) || Application.get_env(:hydra_x, :telegram_deliver)
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
      message: "Telegram delivery failed",
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
      channel != "telegram" -> {:error, {:unsupported_channel, channel}}
      not (is_binary(external_ref) and external_ref != "") -> {:error, :missing_external_ref}
      true -> :ok
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
end
