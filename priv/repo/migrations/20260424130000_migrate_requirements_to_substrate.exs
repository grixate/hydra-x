defmodule HydraX.Repo.Migrations.MigrateRequirementsToSubstrate do
  @moduledoc """
  Phase 1d.3 of the substrate cutover. Drops the `requirements` table
  and repoints `requirement_insights.requirement_id` at `nodes.id`.

  `requirement_insights.insight_id` was already repointed in
  20260424110000. After this migration both endpoints of that join
  live in the generic substrate — `requirement_insights` is now an
  untyped bridge between two node-typed rows, and Phase 1d.5 will
  fold it into generic `node_relationships`.
  """

  use Ecto.Migration

  def up do
    execute "DELETE FROM requirement_insights"

    drop constraint(:requirement_insights, "requirement_insights_requirement_id_fkey")

    alter table(:requirement_insights) do
      modify :requirement_id,
             references(:nodes, on_delete: :delete_all),
             null: false,
             from: {:integer, []}
    end

    drop table(:requirements)
  end

  def down do
    create table(:requirements) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :grounded, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:requirements, [:project_id])
    create index(:requirements, [:status])
    create index(:requirements, [:scope, :scope_root_id])

    drop constraint(:requirement_insights, "requirement_insights_requirement_id_fkey")

    alter table(:requirement_insights) do
      modify :requirement_id, references(:requirements, on_delete: :delete_all), null: false
    end
  end
end
