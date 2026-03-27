defmodule HydraX.Repo.Migrations.AddCronExpressionToScheduledJobs do
  use Ecto.Migration

  def change do
    alter table(:hx_scheduled_jobs) do
      add :cron_expression, :string
    end
  end
end
