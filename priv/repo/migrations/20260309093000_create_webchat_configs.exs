defmodule HydraX.Repo.Migrations.CreateWebchatConfigs do
  use Ecto.Migration

  def change do
    create table(:webchat_configs) do
      add :title, :string
      add :subtitle, :text
      add :welcome_prompt, :text
      add :composer_placeholder, :string
      add :enabled, :boolean, default: false, null: false
      add :default_agent_id, references(:agent_profiles, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
