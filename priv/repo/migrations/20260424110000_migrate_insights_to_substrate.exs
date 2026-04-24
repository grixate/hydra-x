defmodule HydraX.Repo.Migrations.MigrateInsightsToSubstrate do
  @moduledoc """
  Phase 1d.1 of the substrate cutover. Deletes the standalone `insights`
  table and repoints the two join tables (`insight_evidence` and
  `requirement_insights`) so their `insight_id` FK references the new
  unified `nodes` table.

  Per spec §12, no data preservation: existing insight rows are dropped.
  `insight_evidence` and `requirement_insights` rows are cleared because
  their integer references would no longer be valid. Dummy data will be
  regenerated from the domain seed.
  """

  use Ecto.Migration

  def up do
    # Clear dependent data — FKs would be orphaned once `insights` is gone.
    execute "DELETE FROM insight_evidence"
    execute "DELETE FROM requirement_insights"

    # Drop the old FK constraints before re-targeting.
    drop constraint(:insight_evidence, "insight_evidence_insight_id_fkey")
    drop constraint(:requirement_insights, "requirement_insights_insight_id_fkey")

    # Re-add them pointing at `nodes`.
    alter table(:insight_evidence) do
      modify :insight_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    alter table(:requirement_insights) do
      modify :insight_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    # Drop the old table.
    drop table(:insights)
  end

  def down do
    create table(:insights) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:insights, [:project_id])
    create index(:insights, [:status])
    create index(:insights, [:scope, :scope_root_id])

    drop constraint(:insight_evidence, "insight_evidence_insight_id_fkey")
    drop constraint(:requirement_insights, "requirement_insights_insight_id_fkey")

    alter table(:insight_evidence) do
      modify :insight_id, references(:insights, on_delete: :delete_all), null: false
    end

    alter table(:requirement_insights) do
      modify :insight_id, references(:insights, on_delete: :delete_all), null: false
    end
  end
end
