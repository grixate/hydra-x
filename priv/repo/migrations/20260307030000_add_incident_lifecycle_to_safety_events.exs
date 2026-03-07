defmodule HydraX.Repo.Migrations.AddIncidentLifecycleToSafetyEvents do
  use Ecto.Migration

  def change do
    alter table(:safety_events) do
      add :status, :string, default: "open", null: false
      add :acknowledged_at, :utc_datetime_usec
      add :acknowledged_by, :string
      add :resolved_at, :utc_datetime_usec
      add :resolved_by, :string
      add :operator_note, :text
    end

    create index(:safety_events, [:status, :inserted_at])
  end
end
