defmodule HydraX.Repo.Migrations.MigrateVisionsToSubstrate do
  @moduledoc """
  Phase 1k of the substrate cutover. Drops the `visions` table. Visions
  move to `nodes` under `type_key: "vision"`. Uniqueness per project
  (at most one vision per project) is enforced in the `Visions` context
  rather than at the DB level — the unified `nodes` table can host many
  types for the same project, so a global unique (project_id, type_key)
  constraint would also affect other one-of-many types.
  """

  use Ecto.Migration

  def up do
    drop table(:visions)
  end

  def down do
    create table(:visions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:visions, [:project_id])
    create index(:visions, [:status])
  end
end
