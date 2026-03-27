defmodule HydraX.Repo.Migrations.CreateIngestRuns do
  use Ecto.Migration

  def change do
    create table(:hx_ingest_runs) do
      add :agent_id, references(:hx_agent_profiles, on_delete: :delete_all), null: false
      add :source_file, :string, null: false
      add :source_path, :text
      add :status, :string, null: false
      add :chunk_count, :integer, null: false, default: 0
      add :created_count, :integer, null: false, default: 0
      add :skipped_count, :integer, null: false, default: 0
      add :archived_count, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:hx_ingest_runs, [:agent_id, :inserted_at])
    create index(:hx_ingest_runs, [:agent_id, :source_file])
    create index(:hx_ingest_runs, [:status])
  end
end
