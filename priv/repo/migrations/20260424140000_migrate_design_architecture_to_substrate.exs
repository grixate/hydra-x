defmodule HydraX.Repo.Migrations.MigrateDesignArchitectureToSubstrate do
  @moduledoc """
  Phase 1d.4 of the substrate cutover. Drops `design_nodes` and
  `architecture_nodes`. Legacy rows migrate to `nodes` with
  `type_key` of `design_node` / `architecture_node` and the former
  `node_type` discriminator column moves into `attributes`.
  """

  use Ecto.Migration

  def up do
    drop table(:design_nodes)
    drop table(:architecture_nodes)
  end

  def down do
    create table(:design_nodes) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :node_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:design_nodes, [:project_id])
    create index(:design_nodes, [:status])
    create index(:design_nodes, [:node_type])
    create index(:design_nodes, [:scope, :scope_root_id])

    create table(:architecture_nodes) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :node_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:architecture_nodes, [:project_id])
    create index(:architecture_nodes, [:status])
    create index(:architecture_nodes, [:node_type])
    create index(:architecture_nodes, [:scope, :scope_root_id])
  end
end
