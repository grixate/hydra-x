defmodule HydraX.Repo.Migrations.AddAutonomyRuntimeFoundations do
  use Ecto.Migration

  def change do
    alter table(:hx_agent_profiles) do
      add :role, :string, default: "operator", null: false
      add :capability_profile, :map, default: %{}, null: false
    end

    create table(:hx_work_items) do
      add :kind, :string, null: false, default: "task"
      add :goal, :text, null: false
      add :status, :string, null: false, default: "planned"
      add :execution_mode, :string, null: false, default: "execute"
      add :assigned_role, :string, null: false, default: "operator"
      add :priority, :integer, null: false, default: 0
      add :autonomy_level, :string, null: false, default: "recommend"
      add :review_required, :boolean, null: false, default: true
      add :approval_stage, :string, null: false, default: "draft"
      add :deadline_at, :utc_datetime_usec
      add :budget, :map, null: false, default: %{}
      add :input_artifact_refs, :map, null: false, default: %{}
      add :required_outputs, :map, null: false, default: %{}
      add :deliverables, :map, null: false, default: %{}
      add :result_refs, :map, null: false, default: %{}
      add :runtime_state, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :assigned_agent_id, references(:hx_agent_profiles, on_delete: :nilify_all)
      add :delegated_by_agent_id, references(:hx_agent_profiles, on_delete: :nilify_all)
      add :parent_work_item_id, references(:hx_work_items, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_work_items, [:assigned_agent_id])
    create index(:hx_work_items, [:delegated_by_agent_id])
    create index(:hx_work_items, [:parent_work_item_id])
    create index(:hx_work_items, [:status])
    create index(:hx_work_items, [:assigned_role])
    create index(:hx_work_items, [:kind])

    create table(:hx_artifacts) do
      add :type, :string, null: false
      add :title, :string, null: false
      add :summary, :text
      add :body, :text
      add :payload, :map, null: false, default: %{}
      add :version, :integer, null: false, default: 1
      add :provenance, :map, null: false, default: %{}
      add :confidence, :float
      add :review_status, :string, null: false, default: "draft"
      add :metadata, :map, null: false, default: %{}
      add :work_item_id, references(:hx_work_items, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hx_artifacts, [:work_item_id])
    create index(:hx_artifacts, [:type])
  end
end
