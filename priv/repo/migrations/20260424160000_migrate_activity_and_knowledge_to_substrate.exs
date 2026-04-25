defmodule HydraX.Repo.Migrations.MigrateActivityAndKnowledgeToSubstrate do
  @moduledoc """
  Phase 1f of the substrate cutover. Drops `tasks`, `learnings`,
  `knowledge_entries`, and `routines`. Their rows migrate to `nodes`
  under the appropriate `type_key`. Per spec §12 no data preservation;
  embedding vectors from `knowledge_entries` are dropped — re-ingestion
  re-embeds into `node_embeddings`.

  Two join/child tables repoint:
  - `task_feedback.task_id` → `nodes.id`
  - `routine_runs.routine_id` → `nodes.id`
  """

  use Ecto.Migration

  def up do
    execute "DELETE FROM task_feedback"
    execute "DELETE FROM routine_runs"

    drop constraint(:task_feedback, "task_feedback_task_id_fkey")
    drop constraint(:routine_runs, "routine_runs_routine_id_fkey")

    alter table(:task_feedback) do
      modify :task_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    alter table(:routine_runs) do
      modify :routine_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    drop table(:tasks)
    drop table(:learnings)
    drop table(:knowledge_entries)
    drop table(:routines)
  end

  def down do
    create table(:tasks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "backlog"
      add :assignee, :string
      add :effort_estimate, :string
      add :priority, :string, null: false, default: "medium"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:status])
    create index(:tasks, [:priority])

    create table(:learnings) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :learning_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:learnings, [:project_id])
    create index(:learnings, [:status])
    create index(:learnings, [:scope, :scope_root_id])

    create table(:knowledge_entries) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :content, :text, null: false
      add :entry_type, :string, null: false, default: "custom"
      add :assigned_personas, {:array, :string}, null: false, default: []
      add :source_type, :string, null: false, default: "manual"
      add :source_url, :string
      add :status, :string, null: false, default: "active"
      add :embedding, :vector, size: 768
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:knowledge_entries, [:project_id])
    create index(:knowledge_entries, [:status])
    create index(:knowledge_entries, [:entry_type])

    create table(:routines) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :prompt_template, :text, null: false
      add :assigned_persona, :string, null: false
      add :schedule_type, :string, null: false, default: "cron"
      add :cron_expression, :string
      add :event_trigger, :string
      add :timezone, :string, default: "UTC"
      add :output_target, :string, default: "stream_item"
      add :status, :string, null: false, default: "active"
      add :last_run_at, :utc_datetime
      add :last_run_status, :string
      add :last_run_tokens, :integer
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:routines, [:project_id])
    create index(:routines, [:status])

    drop constraint(:task_feedback, "task_feedback_task_id_fkey")
    drop constraint(:routine_runs, "routine_runs_routine_id_fkey")

    alter table(:task_feedback) do
      modify :task_id, references(:tasks, on_delete: :delete_all), null: false
    end

    alter table(:routine_runs) do
      modify :routine_id, references(:routines, on_delete: :delete_all), null: false
    end
  end
end
