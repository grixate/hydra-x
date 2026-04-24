defmodule HydraX.Repo.Migrations.MigrateSimpleClaimsToSubstrate do
  @moduledoc """
  Phase 1d.2 of the substrate cutover. Drops the `decisions`,
  `strategies`, and `constraints` tables. Their rows migrate to the
  unified `nodes` table with `type_key` set accordingly. Per spec §12
  no data preservation — existing rows are dropped and regenerated
  from dummy data.

  No foreign keys point into these tables (verified via grep), so a
  straight drop is safe.
  """

  use Ecto.Migration

  def up do
    drop table(:decisions)
    drop table(:strategies)
    drop table(:constraints)
  end

  def down do
    create table(:decisions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"
      add :decided_by, :string
      add :decided_at, :utc_datetime
      add :alternatives_considered, :jsonb, null: false, default: "[]"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:decisions, [:project_id])
    create index(:decisions, [:status])
    create index(:decisions, [:scope, :scope_root_id])

    create table(:strategies) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:strategies, [:project_id])
    create index(:strategies, [:status])
    create index(:strategies, [:scope, :scope_root_id])

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
  end
end
