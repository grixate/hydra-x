defmodule HydraX.Runtime.DiscordAdmin do
  @moduledoc """
  Discord configuration CRUD.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Gateway.Adapters.Discord
  alias HydraX.Security.Secrets
  alias HydraX.Runtime.{DiscordConfig, Helpers}

  def enabled_discord_config do
    DiscordConfig
    |> where([config], config.enabled == true)
    |> preload([:default_agent])
    |> limit(1)
    |> Repo.one()
    |> decrypt_config()
  end

  def list_discord_configs do
    DiscordConfig
    |> preload([:default_agent])
    |> order_by([config], desc: config.enabled, desc: config.updated_at)
    |> Repo.all()
    |> Enum.map(&decrypt_config/1)
  end

  def change_discord_config(config \\ %DiscordConfig{}, attrs \\ %{}) do
    DiscordConfig.changeset(decrypt_config(config), attrs)
  end

  def save_discord_config(attrs) when is_map(attrs) do
    config =
      enabled_discord_config() || List.first(list_discord_configs()) || %DiscordConfig{}

    save_discord_config(config, attrs)
  end

  def save_discord_config(%DiscordConfig{} = config, attrs) do
    Repo.transaction(fn ->
      decrypted = decrypt_config(config)

      encrypted_attrs =
        attrs
        |> Helpers.normalize_string_keys()
        |> Secrets.encrypt_secret_attrs(decrypted, [:bot_token, :webhook_secret])

      changeset = DiscordConfig.changeset(config, encrypted_attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> decrypt_config(record)
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in DiscordConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      Repo.preload(record, [:default_agent])
    end)
    |> Helpers.unwrap_transaction()
  end

  def test_discord_delivery(%DiscordConfig{} = config, target, message, opts \\ []) do
    config = decrypt_config(config)

    with true <- is_binary(target) and target != "",
         {:ok, state} <-
           Discord.connect(%{
             "bot_token" => config.bot_token,
             "application_id" => config.application_id,
             "webhook_secret" => config.webhook_secret,
             "deliver" =>
               Keyword.get(opts, :deliver) || Application.get_env(:hydra_x, :discord_deliver)
           }),
         {:ok, metadata} <-
           Discord.deliver(%{content: message, external_ref: target}, state) do
      {:ok, %{target: target, message: message, metadata: metadata}}
    else
      false -> {:error, :missing_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decrypt_config(nil), do: nil

  defp decrypt_config(%DiscordConfig{} = config) do
    Secrets.decrypt_fields(config, [:bot_token, :webhook_secret])
  end
end
