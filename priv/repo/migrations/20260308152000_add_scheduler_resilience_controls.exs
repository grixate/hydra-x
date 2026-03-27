defmodule HydraX.Repo.Migrations.AddSchedulerResilienceControls do
  use Ecto.Migration

  def change do
    alter table(:hx_scheduled_jobs) do
      add :active_hour_start, :integer
      add :active_hour_end, :integer
      add :timeout_seconds, :integer, null: false, default: 120
      add :retry_limit, :integer, null: false, default: 0
      add :retry_backoff_seconds, :integer, null: false, default: 0
      add :pause_after_failures, :integer, null: false, default: 0
      add :cooldown_minutes, :integer, null: false, default: 0
      add :consecutive_failures, :integer, null: false, default: 0
      add :circuit_state, :string, null: false, default: "closed"
      add :circuit_opened_at, :utc_datetime_usec
      add :paused_until, :utc_datetime_usec
      add :last_failure_at, :utc_datetime_usec
      add :last_failure_reason, :text
    end

    create index(:hx_scheduled_jobs, [:circuit_state])
    create index(:hx_scheduled_jobs, [:paused_until])
  end
end
