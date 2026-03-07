defmodule Mix.Tasks.HydraX.Telegram.Webhook do
  use Mix.Task

  @shortdoc "Shows or registers the Telegram webhook"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()

    case args do
      ["delete"] ->
        delete()

      ["register"] ->
        register()

      ["sync"] ->
        sync()

      ["test", chat_id, message] ->
        test_delivery(chat_id, message)

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

    if status.last_checked_at do
      Mix.shell().info(
        "Last checked at: #{Calendar.strftime(status.last_checked_at, "%Y-%m-%d %H:%M:%S UTC")}"
      )
    end

    Mix.shell().info("Pending updates: #{status.pending_update_count}")
    Mix.shell().info("Retryable failed deliveries: #{status.retryable_count}")

    if status.last_error do
      Mix.shell().info("Last error: #{status.last_error}")
    end

    Enum.each(status.recent_failures, fn failure ->
      Mix.shell().info(
        "Failed conversation ##{failure.id}: #{failure.title} (retry #{failure.retry_count})"
      )
    end)
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

  defp sync do
    case HydraX.Runtime.enabled_telegram_config() ||
           List.first(HydraX.Runtime.list_telegram_configs()) do
      nil ->
        Mix.raise("No Telegram config found. Configure it in /setup first.")

      config ->
        case HydraX.Runtime.sync_telegram_webhook_info(config) do
          {:ok, updated} ->
            Mix.shell().info("Webhook status refreshed for #{updated.webhook_url}")

          {:error, reason} ->
            Mix.raise("Telegram webhook sync failed: #{inspect(reason)}")
        end
    end
  end

  defp delete do
    case HydraX.Runtime.enabled_telegram_config() ||
           List.first(HydraX.Runtime.list_telegram_configs()) do
      nil ->
        Mix.raise("No Telegram config found. Configure it in /setup first.")

      config ->
        case HydraX.Runtime.delete_telegram_webhook(config) do
          {:ok, _updated} ->
            Mix.shell().info("Deleted Telegram webhook")

          {:error, reason} ->
            Mix.raise("Telegram webhook deletion failed: #{inspect(reason)}")
        end
    end
  end

  defp test_delivery(chat_id, message) do
    case HydraX.Runtime.enabled_telegram_config() ||
           List.first(HydraX.Runtime.list_telegram_configs()) do
      nil ->
        Mix.raise("No Telegram config found. Configure it in /setup first.")

      config ->
        case HydraX.Runtime.test_telegram_delivery(config, chat_id, message) do
          {:ok, result} ->
            Mix.shell().info("Delivered test message to #{result.target}")
            Mix.shell().info("metadata=#{inspect(result.metadata)}")

          {:error, reason} ->
            Mix.raise("Telegram delivery test failed: #{inspect(reason)}")
        end
    end
  end
end
