defmodule HydraX.Repo.Migrations.CreateSkillInstalls do
  use Ecto.Migration

  def change do
    create table(:hx_skill_installs) do
      add :agent_id, references(:hx_agent_profiles, on_delete: :delete_all), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :path, :string, null: false
      add :description, :text
      add :source, :string, null: false, default: "workspace"
      add :enabled, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:hx_skill_installs, [:agent_id, :slug])
    create index(:hx_skill_installs, [:agent_id, :enabled])
  end
end
