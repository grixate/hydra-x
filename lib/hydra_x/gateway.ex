defmodule HydraX.Gateway do
  @moduledoc """
  Routes inbound adapter messages into agent conversations.
  """

  alias HydraX.Gateway.Adapters.Telegram
  alias HydraX.Runtime
  alias HydraX.Safety

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
      "deliver" => Map.get(opts, :deliver)
    }
  end

  defp record_delivery_result(_agent_id, conversation, message, {:ok, metadata})
       when is_map(metadata) do
    Runtime.update_conversation_metadata(conversation, %{
      "last_delivery" => %{
        "channel" => message.channel,
        "status" => "delivered",
        "external_ref" => message.external_ref,
        "delivered_at" => DateTime.utc_now(),
        "metadata" => stringify_keys(metadata)
      }
    })
  end

  defp record_delivery_result(agent_id, conversation, message, :ok) do
    record_delivery_result(agent_id, conversation, message, {:ok, %{}})
  end

  defp record_delivery_result(agent_id, conversation, message, {:error, reason}) do
    reason_text = inspect(reason)

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

    Runtime.update_conversation_metadata(conversation, %{
      "last_delivery" => %{
        "channel" => message.channel,
        "status" => "failed",
        "external_ref" => message.external_ref,
        "attempted_at" => DateTime.utc_now(),
        "reason" => reason_text
      }
    })
  end

  defp stringify_keys(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
