defmodule HydraX.Runtime.WebchatAdmin do
  @moduledoc """
  Webchat configuration CRUD.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.{Helpers, WebchatConfig}

  def enabled_webchat_config do
    WebchatConfig
    |> where([config], config.enabled == true)
    |> preload([:default_agent])
    |> limit(1)
    |> Repo.one()
  end

  def list_webchat_configs do
    WebchatConfig
    |> preload([:default_agent])
    |> order_by([config], desc: config.enabled, desc: config.updated_at)
    |> Repo.all()
  end

  def change_webchat_config(config \\ %WebchatConfig{}, attrs \\ %{}) do
    WebchatConfig.changeset(config, attrs)
  end

  def save_webchat_config(attrs) when is_map(attrs) do
    config = enabled_webchat_config() || List.first(list_webchat_configs()) || %WebchatConfig{}
    save_webchat_config(config, attrs)
  end

  def save_webchat_config(%WebchatConfig{} = config, attrs) do
    Repo.transaction(fn ->
      changeset = WebchatConfig.changeset(config, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in WebchatConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      Repo.preload(record, [:default_agent])
    end)
    |> Helpers.unwrap_transaction()
  end
end
