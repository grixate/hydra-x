defmodule HydraX.Runtime.TelegramAdmin do
  @moduledoc """
  Telegram configuration, webhook management, and delivery testing.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Repo

  alias HydraX.Gateway.Adapters.Telegram
  alias HydraX.Runtime.{Helpers, TelegramConfig}

  def enabled_telegram_config do
    TelegramConfig
    |> where([config], config.enabled == true)
    |> preload([:default_agent])
    |> limit(1)
    |> Repo.one()
  end

  def list_telegram_configs do
    TelegramConfig
    |> preload([:default_agent])
    |> order_by([config], desc: config.enabled, desc: config.updated_at)
    |> Repo.all()
  end

  def change_telegram_config(config \\ %TelegramConfig{}, attrs \\ %{}) do
    TelegramConfig.changeset(config, attrs)
  end

  def save_telegram_config(attrs) when is_map(attrs) do
    config =
      enabled_telegram_config() || List.first(list_telegram_configs()) || %TelegramConfig{}

    save_telegram_config(config, attrs)
  end

  def save_telegram_config(%TelegramConfig{} = config, attrs) do
    Repo.transaction(fn ->
      changeset = TelegramConfig.changeset(config, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in TelegramConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      Repo.preload(record, [:default_agent])
    end)
    |> Helpers.unwrap_transaction()
  end

  def register_telegram_webhook(%TelegramConfig{} = config, opts \\ []) do
    url = Keyword.get(opts, :url, Config.telegram_webhook_url())
    request_fn = Keyword.get(opts, :request_fn, &Telegram.register_webhook/4)

    with true <- config.bot_token not in [nil, ""],
         :ok <- request_fn.(config.bot_token, url, config.webhook_secret, opts),
         {:ok, updated} <-
           save_telegram_config(config, %{
             webhook_url: url,
             webhook_registered_at: DateTime.utc_now(),
             webhook_last_checked_at: DateTime.utc_now(),
             webhook_last_error: nil,
             enabled: true
           }) do
      Helpers.audit_operator_action(
        "Registered Telegram webhook",
        agent_id: updated.default_agent_id,
        metadata: %{"webhook_url" => updated.webhook_url}
      )

      {:ok, updated}
    else
      false -> {:error, :missing_bot_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_telegram_webhook_info(%TelegramConfig{} = config, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Telegram.webhook_info/2)

    with true <- config.bot_token not in [nil, ""],
         {:ok, result} <- request_fn.(config.bot_token, opts),
         {:ok, updated} <-
           save_telegram_config(config, %{
             webhook_last_checked_at: DateTime.utc_now(),
             webhook_pending_update_count: result["pending_update_count"] || 0,
             webhook_last_error: Helpers.blank_to_nil(result["last_error_message"]),
             webhook_url: Helpers.blank_to_nil(result["url"]) || config.webhook_url
           }) do
      Helpers.audit_operator_action(
        "Synced Telegram webhook status",
        agent_id: updated.default_agent_id,
        metadata: %{
          "pending_update_count" => updated.webhook_pending_update_count || 0,
          "webhook_url" => updated.webhook_url
        }
      )

      {:ok, updated}
    else
      false ->
        {:error, :missing_bot_token}

      {:error, reason} ->
        save_telegram_config(config, %{
          webhook_last_checked_at: DateTime.utc_now(),
          webhook_last_error: inspect(reason)
        })

        {:error, reason}
    end
  end

  def delete_telegram_webhook(%TelegramConfig{} = config, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Telegram.delete_webhook/2)

    with true <- config.bot_token not in [nil, ""],
         :ok <- request_fn.(config.bot_token, opts),
         {:ok, updated} <-
           save_telegram_config(config, %{
             enabled: false,
             webhook_registered_at: nil,
             webhook_last_checked_at: DateTime.utc_now(),
             webhook_pending_update_count: 0,
             webhook_last_error: nil
           }) do
      Helpers.audit_operator_action(
        "Removed Telegram webhook",
        agent_id: updated.default_agent_id,
        metadata: %{"webhook_url" => updated.webhook_url}
      )

      {:ok, updated}
    else
      false -> {:error, :missing_bot_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def test_telegram_delivery(%TelegramConfig{} = config, target, message, opts \\ []) do
    target = Helpers.blank_to_nil(to_string(target || ""))
    message = Helpers.blank_to_nil(message)
    deliver = Keyword.get(opts, :deliver, Application.get_env(:hydra_x, :telegram_deliver))

    cond do
      is_nil(target) ->
        {:error, :missing_target}

      is_nil(message) ->
        {:error, :missing_message}

      Helpers.blank_to_nil(config.bot_token) == nil ->
        {:error, :missing_bot_token}

      true ->
        with {:ok, state} <-
               Telegram.connect(%{
                 "bot_token" => config.bot_token,
                 "bot_username" => config.bot_username,
                 "webhook_secret" => config.webhook_secret,
                 "deliver" => deliver
               }),
             {:ok, metadata} <-
               Telegram.send_response(%{content: message, external_ref: target}, state) do
          Helpers.audit_operator_action(
            "Sent Telegram smoke test to #{target}",
            agent_id: config.default_agent_id,
            metadata: %{"channel" => "telegram", "target" => target}
          )

          {:ok, %{target: target, message: message, metadata: metadata}}
        end
    end
  end
end
