defmodule HydraX.Repo.Migrations.AddWeeklyScheduleToJobs do
  use Ecto.Migration

  def change do
    alter table(:hx_scheduled_jobs) do
      add :schedule_mode, :string, null: false, default: "interval"
      add :weekday_csv, :string
      add :run_hour, :integer
      add :run_minute, :integer
    end
  end
end
