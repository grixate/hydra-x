defmodule HydraX.Gateway do
  @moduledoc """
  Routes inbound adapter messages into agent conversations.
  """

  alias HydraX.Gateway.Adapters.Telegram
  alias HydraX.Runtime

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

    Telegram.send_response(%{content: response, external_ref: message.external_ref}, state)
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
end
