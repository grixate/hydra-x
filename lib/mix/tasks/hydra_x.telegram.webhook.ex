defmodule Mix.Tasks.HydraX.Telegram.Webhook do
  use Mix.Task

  @shortdoc "Shows or registers the Telegram webhook"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()

    case args do
      ["register"] ->
        register()

      _ ->
        show()
    end
  end

  defp show do
    status = HydraX.Runtime.telegram_status()

    Mix.shell().info("Telegram configured: #{status.configured}")
    Mix.shell().info("Telegram enabled: #{status.enabled}")
    Mix.shell().info("Webhook URL: #{status.webhook_url}")

    if status.bot_username do
      Mix.shell().info("Bot username: @#{status.bot_username}")
    end

    if status.default_agent_name do
      Mix.shell().info("Default agent: #{status.default_agent_name}")
    end

    if status.registered_at do
      Mix.shell().info(
        "Registered at: #{Calendar.strftime(status.registered_at, "%Y-%m-%d %H:%M:%S UTC")}"
      )
    end
  end

  defp register do
    case HydraX.Runtime.enabled_telegram_config() ||
           List.first(HydraX.Runtime.list_telegram_configs()) do
      nil ->
        Mix.raise("No Telegram config found. Configure it in /setup first.")

      config ->
        case HydraX.Runtime.register_telegram_webhook(config) do
          {:ok, updated} ->
            Mix.shell().info("Registered Telegram webhook: #{updated.webhook_url}")

          {:error, reason} ->
            Mix.raise("Telegram webhook registration failed: #{inspect(reason)}")
        end
    end
  end
end
