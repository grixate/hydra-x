defmodule HydraX.Repo.Migrations.CreateVisions do
  @moduledoc """
  Stream A0.1 — Real Vision node type.

  Previously the Why-button + onboarding synthesized a "Vision" from
  `project.description`. Per Stream A, the Vision becomes a proper typed
  graph node. Backfills a Vision row for any existing project whose
  description is non-empty.

  Scope: one Vision per project (enforced by unique index on project_id).
  """

  use Ecto.Migration

  def up do
    create table(:visions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:visions, [:project_id])
    create index(:visions, [:scope, :scope_root_id])

    # Backfill: every project with a non-empty description becomes a Vision.
    execute """
    INSERT INTO visions (project_id, title, body, status, metadata, scope, scope_root_id, inserted_at, updated_at)
    SELECT
      id,
      name,
      description,
      'active',
      '{}'::jsonb,
      'project',
      id,
      NOW(),
      NOW()
    FROM projects
    WHERE description IS NOT NULL AND description <> ''
    ON CONFLICT (project_id) DO NOTHING
    """
  end

  def down do
    drop table(:visions)
  end
end
