defmodule HydraX.Repo.Migrations.AddRunRetentionDaysToScheduledJobs do
  use Ecto.Migration

  def change do
    alter table(:scheduled_jobs) do
      add :run_retention_days, :integer, null: false, default: 30
    end
  end
end
