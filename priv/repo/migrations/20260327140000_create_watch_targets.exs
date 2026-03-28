defmodule HydraX.Repo.Migrations.CreateWatchTargets do
  use Ecto.Migration

  def change do
    create table(:watch_targets) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :target_type, :string, null: false
      add :value, :string, null: false
      add :check_interval_hours, :integer, null: false, default: 24
      add :last_checked_at, :utc_datetime
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:watch_targets, [:project_id])
    create index(:watch_targets, [:status])
  end
end
