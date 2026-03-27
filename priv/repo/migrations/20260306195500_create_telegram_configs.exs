defmodule HydraX.Repo.Migrations.CreateTelegramConfigs do
  use Ecto.Migration

  def change do
    create table(:hx_telegram_configs) do
      add :bot_token, :text, null: false
      add :bot_username, :string
      add :webhook_secret, :string
      add :enabled, :boolean, null: false, default: false
      add :default_agent_id, references(:hx_agent_profiles, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_telegram_configs, [:default_agent_id])
  end
end
