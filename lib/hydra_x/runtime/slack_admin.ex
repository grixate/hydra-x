defmodule HydraX.Runtime.SlackAdmin do
  @moduledoc """
  Slack configuration CRUD.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.{Helpers, SlackConfig}

  def enabled_slack_config do
    SlackConfig
    |> where([config], config.enabled == true)
    |> preload([:default_agent])
    |> limit(1)
    |> Repo.one()
  end

  def list_slack_configs do
    SlackConfig
    |> preload([:default_agent])
    |> order_by([config], desc: config.enabled, desc: config.updated_at)
    |> Repo.all()
  end

  def change_slack_config(config \\ %SlackConfig{}, attrs \\ %{}) do
    SlackConfig.changeset(config, attrs)
  end

  def save_slack_config(attrs) when is_map(attrs) do
    config =
      enabled_slack_config() || List.first(list_slack_configs()) || %SlackConfig{}

    save_slack_config(config, attrs)
  end

  def save_slack_config(%SlackConfig{} = config, attrs) do
    Repo.transaction(fn ->
      changeset = SlackConfig.changeset(config, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in SlackConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      Repo.preload(record, [:default_agent])
    end)
    |> Helpers.unwrap_transaction()
  end
end
