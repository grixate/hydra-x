defmodule HydraX.Repo.Migrations.CreateMentionsAndFlows do
  use Ecto.Migration

  def change do
    create table(:flows) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :originating_task_id, references(:agent_tasks, on_delete: :nilify_all)
      add :status, :string, null: false, default: "ongoing"
      add :participating_agent_ids, {:array, :string}, null: false, default: []
      add :task_ids, {:array, :integer}, null: false, default: []
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:flows, [:project_id, :status])
    create index(:flows, [:originating_task_id])

    create table(:mentions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :source_task_id, references(:agent_tasks, on_delete: :nilify_all)
      add :source_message_id, :integer
      add :source_agent_id, :string
      add :source_user_id, :integer
      add :target_agent_id, :string, null: false
      add :target_task_id, references(:agent_tasks, on_delete: :nilify_all)
      add :content, :text
      add :intent, :string, null: false, default: "share_context"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:mentions, [:project_id, :source_task_id])
    create index(:mentions, [:project_id, :target_task_id])
    create index(:mentions, [:project_id, :target_agent_id, :inserted_at])

    alter table(:agent_tasks) do
      add :originating_mention_id, references(:mentions, on_delete: :nilify_all)
      add :flow_id, references(:flows, on_delete: :nilify_all)
    end

    create index(:agent_tasks, [:flow_id])
  end
end
