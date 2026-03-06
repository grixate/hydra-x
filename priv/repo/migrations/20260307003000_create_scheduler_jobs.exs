defmodule HydraX.Repo.Migrations.CreateSchedulerJobs do
  use Ecto.Migration

  def change do
    create table(:scheduled_jobs) do
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :prompt, :text
      add :interval_minutes, :integer, null: false, default: 60
      add :enabled, :boolean, null: false, default: true
      add :next_run_at, :utc_datetime_usec
      add :last_run_at, :utc_datetime_usec
      add :config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_jobs, [:agent_id])
    create index(:scheduled_jobs, [:enabled, :next_run_at])

    create table(:job_runs) do
      add :scheduled_job_id, references(:scheduled_jobs, on_delete: :delete_all), null: false
      add :agent_id, references(:agent_profiles, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :output, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:job_runs, [:scheduled_job_id])
    create index(:job_runs, [:agent_id])
    create index(:job_runs, [:inserted_at])
  end
end
