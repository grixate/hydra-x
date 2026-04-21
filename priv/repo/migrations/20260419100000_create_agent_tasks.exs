defmodule HydraX.Repo.Migrations.CreateAgentTasks do
  use Ecto.Migration

  def change do
    create table(:agent_tasks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :agent_id, :string, null: false
      add :title, :string, null: false
      add :description, :text

      add :state, :string, null: false, default: "pending"
      add :state_reason, :text
      add :priority, :string, null: false, default: "normal"

      add :progress_current, :integer
      add :progress_total, :integer
      add :progress_label, :string

      add :context_type, :string
      add :context_id, :integer

      add :parent_task_id, references(:agent_tasks, on_delete: :nilify_all)

      add :assigned_by, :string, null: false, default: "user"
      add :assigned_by_user_id, :integer
      add :assigned_by_agent_id, :string

      add :proposal_payload, :map
      add :result_payload, :map
      add :error_payload, :map

      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :last_state_change_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_tasks, [:project_id, :state])
    create index(:agent_tasks, [:project_id, :agent_id, :state])
    create index(:agent_tasks, [:project_id, :last_state_change_at])
    create index(:agent_tasks, [:parent_task_id])

    create table(:task_events) do
      add :task_id, references(:agent_tasks, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :actor_type, :string, null: false
      add :actor_id, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:task_events, [:task_id, :inserted_at])
    create index(:task_events, [:project_id, :inserted_at])
  end
end
