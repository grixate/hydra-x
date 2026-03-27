defmodule HydraX.Repo.Migrations.AddDeliveryFieldsToScheduledJobs do
  use Ecto.Migration

  def up do
    existing_columns = scheduled_job_columns()

    unless "delivery_enabled" in existing_columns do
      execute(
        "ALTER TABLE hx_scheduled_jobs ADD COLUMN delivery_enabled boolean DEFAULT false NOT NULL"
      )
    end

    unless "delivery_channel" in existing_columns do
      execute("ALTER TABLE hx_scheduled_jobs ADD COLUMN delivery_channel text")
    end

    unless "delivery_target" in existing_columns do
      execute("ALTER TABLE hx_scheduled_jobs ADD COLUMN delivery_target text")
    end
  end

  def down, do: :ok

  defp scheduled_job_columns do
    repo().query!("""
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'hx_scheduled_jobs'
    """)
    |> Map.fetch!(:rows)
    |> Enum.map(fn [name] -> name end)
  end
end
