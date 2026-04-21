defmodule HydraX.Repo.Migrations.AddScopeToNodes do
  @moduledoc """
  Architecture-only preparation for Cycle 2 Shared Memory. Adds `scope` and
  `scope_root_id` to every typed graph-node table so the schema can carry
  future "shared"-scoped nodes without another migration.

  Per Shared Memory spec §9:
    * Default all nodes to `scope = "project"`
    * Backfill `scope_root_id = project_id` on existing rows
    * No UI, no SharedScope entity, no Distillation entity yet.

  NOTE: `constraints` is intentionally excluded. That table already owns a
  `scope` column (global / technical / design / process / business) that
  names the constraint's *reach*, not its memory scope. Cycle 2 will rename
  the existing field to `scope_type` and add memory scope cleanly. Until
  then constraints are implicitly project-scoped like everything else.
  """

  use Ecto.Migration

  @tables ~w(
    insights
    requirements
    decisions
    strategies
    design_nodes
    architecture_nodes
    learnings
    product_simulations
  )a

  def up do
    for table <- @tables do
      alter table(table) do
        add :scope, :string, null: false, default: "project"
        add :scope_root_id, :integer
      end

      execute("UPDATE #{table} SET scope_root_id = project_id WHERE scope_root_id IS NULL")

      alter table(table) do
        modify :scope_root_id, :integer, null: false
      end

      create index(table, [:scope, :scope_root_id])
    end
  end

  def down do
    for table <- @tables do
      drop_if_exists index(table, [:scope, :scope_root_id])

      alter table(table) do
        remove :scope_root_id
        remove :scope
      end
    end
  end
end
