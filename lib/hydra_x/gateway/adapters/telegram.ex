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

  defp do_send_response(content, external_ref, _token, deliver) when is_function(deliver, 1) do
    deliver.(%{content: content, external_ref: external_ref})
  end

  defp do_send_response(content, external_ref, token, _deliver) do
    case Req.post(
           url: "https://api.telegram.org/bot#{token}/sendMessage",
           form: [chat_id: external_ref, text: content]
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, response} -> {:error, {:telegram_error, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_secret(body, nil), do: body
  defp maybe_put_secret(body, ""), do: body
  defp maybe_put_secret(body, secret), do: Map.put(body, :secret_token, secret)
end
