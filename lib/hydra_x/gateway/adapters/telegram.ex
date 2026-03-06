defmodule HydraX.Gateway.Adapters.Telegram do
  @moduledoc """
  Telegram adapter skeleton with request/response mapping.
  """

  @behaviour HydraX.Gateway.Adapter

  @impl true
  def connect(%{"bot_token" => token}) when is_binary(token) and token != "" do
    {:ok, %{bot_token: token}}
  end

  def connect(_config), do: {:error, :missing_bot_token}

  @impl true
  def handle_event(%{"message" => %{"chat" => %{"id" => chat_id}, "text" => text}} = event, state) do
    message = %{
      channel: "telegram",
      external_ref: to_string(chat_id),
      content: text,
      metadata: %{raw: event}
    }

    {:messages, [message], state}
  end

  def handle_event(_event, state), do: {:messages, [], state}

  @impl true
  def send_response(%{content: content, external_ref: external_ref}, %{bot_token: token}) do
    case Req.post(
           url: "https://api.telegram.org/bot#{token}/sendMessage",
           form: [chat_id: external_ref, text: content]
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, response} -> {:error, {:telegram_error, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
