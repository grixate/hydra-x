defmodule HydraX.Repo.Migrations.AddDeliveryFieldsToScheduledJobs do
  use Ecto.Migration

  def up do
    existing_columns = scheduled_job_columns()

    unless "delivery_enabled" in existing_columns do
      execute(
        "ALTER TABLE scheduled_jobs ADD COLUMN delivery_enabled INTEGER DEFAULT false NOT NULL"
      )
    end

    unless "delivery_channel" in existing_columns do
      execute("ALTER TABLE scheduled_jobs ADD COLUMN delivery_channel TEXT")
    end

    unless "delivery_target" in existing_columns do
      execute("ALTER TABLE scheduled_jobs ADD COLUMN delivery_target TEXT")
    end
  end

  def down, do: :ok

  defp scheduled_job_columns do
    repo().query!("PRAGMA table_info('scheduled_jobs')")
    |> Map.fetch!(:rows)
    |> Enum.map(fn [_cid, name | _rest] -> name end)
  end
end
