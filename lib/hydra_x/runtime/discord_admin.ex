defmodule HydraX.Runtime.DiscordAdmin do
  @moduledoc """
  Discord configuration CRUD.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.{DiscordConfig, Helpers}

  def enabled_discord_config do
    DiscordConfig
    |> where([config], config.enabled == true)
    |> preload([:default_agent])
    |> limit(1)
    |> Repo.one()
  end

  def list_discord_configs do
    DiscordConfig
    |> preload([:default_agent])
    |> order_by([config], desc: config.enabled, desc: config.updated_at)
    |> Repo.all()
  end

  def change_discord_config(config \\ %DiscordConfig{}, attrs \\ %{}) do
    DiscordConfig.changeset(config, attrs)
  end

  def save_discord_config(attrs) when is_map(attrs) do
    config =
      enabled_discord_config() || List.first(list_discord_configs()) || %DiscordConfig{}

    save_discord_config(config, attrs)
  end

  def save_discord_config(%DiscordConfig{} = config, attrs) do
    Repo.transaction(fn ->
      changeset = DiscordConfig.changeset(config, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
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
end
