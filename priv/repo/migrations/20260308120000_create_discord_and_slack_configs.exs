defmodule HydraX.Repo.Migrations.CreateDiscordAndSlackConfigs do
  use Ecto.Migration

  def change do
    create table(:hx_discord_configs) do
      add :bot_token, :string, null: false
      add :application_id, :string
      add :webhook_secret, :string
      add :enabled, :boolean, default: false, null: false
      add :default_agent_id, references(:hx_agent_profiles, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:hx_slack_configs) do
      add :bot_token, :string, null: false
      add :signing_secret, :string
      add :enabled, :boolean, default: false, null: false
      add :default_agent_id, references(:hx_agent_profiles, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
