defmodule HydraX.Repo.Migrations.CreatePhase2Schemas do
  use Ecto.Migration

  def change do
    # Constraints — non-negotiable project boundaries
    create table(:constraints) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :scope, :string, null: false, default: "global"
      add :enforcement, :string, null: false, default: "strict"
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:constraints, [:project_id])
    create index(:constraints, [:status])

    # Routines — recurring scheduled agent tasks
    create table(:routines) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :prompt_template, :text, null: false
      add :assigned_persona, :string, null: false
      add :schedule_type, :string, null: false, default: "cron"
      add :cron_expression, :string
      add :event_trigger, :string
      add :timezone, :string, null: false, default: "UTC"
      add :output_target, :string, null: false, default: "stream_item"
      add :status, :string, null: false, default: "active"
      add :last_run_at, :utc_datetime
      add :last_run_status, :string
      add :last_run_tokens, :integer
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:routines, [:project_id])
    create index(:routines, [:status])

    # Routine runs — execution traces
    create table(:routine_runs) do
      add :routine_id, references(:routines, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :status, :string, null: false, default: "running"
      add :prompt_resolved, :text
      add :output, :text
      add :token_count, :integer
      add :cost_cents, :integer
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:routine_runs, [:routine_id])
    create index(:routine_runs, [:status])

    # Knowledge entries — curated agent reference material
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

    # Task feedback — human ratings on completed tasks
    create table(:task_feedback) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :rating, :string, null: false
      add :comment, :text
      add :feedback_tags, {:array, :string}, null: false, default: []
      add :created_by, :string, null: false, default: "human"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:task_feedback, [:task_id])

    # Add trust_level to projects
    alter table(:projects) do
      add :trust_level, :string, null: false, default: "standard"
    end

    # Add pending to graph edge node types and constraint to the list
    # (No migration needed — these are Ecto-level validations, not DB constraints)

    # Add search vectors for constraints and knowledge_entries
    execute("""
    ALTER TABLE constraints
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(body, '')), 'B')
    ) STORED
    """)

    create index(:constraints, [:search_vector], using: :gin)
  end
end
