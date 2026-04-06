defmodule HydraX.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :artifact_type, :string, null: false
      add :body, :text, null: false
      add :owner_persona, :string, null: false
      add :status, :string, null: false, default: "active"
      add :version, :integer, null: false, default: 1
      add :last_updated_by, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifacts, [:project_id])
    create index(:artifacts, [:project_id, :artifact_type])
    create index(:artifacts, [:project_id, :status])

    create table(:artifact_versions) do
      add :artifact_id, references(:artifacts, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :body, :text, null: false
      add :change_summary, :string
      add :updated_by, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifact_versions, [:artifact_id])
    create index(:artifact_versions, [:artifact_id, :version], unique: true)
  end
end
