defmodule HydraX.Repo.Migrations.CreateStreamEntries do
  use Ecto.Migration

  def change do
    create table(:stream_entries) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :tab, :string, null: false
      add :source_task_id, references(:agent_tasks, on_delete: :nilify_all)
      add :source_agent_id, :string
      add :title, :string, null: false
      add :summary, :text
      add :context_type, :string
      add :context_id, :integer
      add :read_at, :utc_datetime_usec
      add :actioned_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:stream_entries, [:project_id, :tab, :inserted_at])
    create index(:stream_entries, [:source_task_id])
  end
end
