defmodule HydraX.Repo.Migrations.MigrateArtifactsToSubstrate do
  @moduledoc """
  Phase 1d.5 of the substrate cutover. Drops `artifacts` and repoints
  `artifact_versions.artifact_id` at `nodes.id`. Artifacts move to the
  substrate with `type_key: "artifact"`. The `artifact_type`,
  `owner_persona`, and `last_updated_by` fields fold into `attributes`.

  The artifact's integer `version` column — which doubled as the
  optimistic lock counter and the current version number — maps to the
  substrate's `lock_version` column. ArtifactVersion rows continue to
  record history with their own per-row version integer.
  """

  use Ecto.Migration

  def up do
    execute "DELETE FROM artifact_versions"

    drop constraint(:artifact_versions, "artifact_versions_artifact_id_fkey")

    alter table(:artifact_versions) do
      modify :artifact_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    drop table(:artifacts)
  end

  def down do
    create table(:artifacts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :artifact_type, :string, null: false
      add :body, :text, null: false
      add :owner_persona, :string, null: false
      add :status, :string, null: false, default: "active"
      add :version, :integer, null: false, default: 1
      add :last_updated_by, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifacts, [:project_id])
    create index(:artifacts, [:status])

    drop constraint(:artifact_versions, "artifact_versions_artifact_id_fkey")

    alter table(:artifact_versions) do
      modify :artifact_id, references(:artifacts, on_delete: :delete_all), null: false
    end
  end
end
