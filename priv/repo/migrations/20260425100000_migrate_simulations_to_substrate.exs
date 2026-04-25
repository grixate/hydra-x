defmodule HydraX.Repo.Migrations.MigrateSimulationsToSubstrate do
  @moduledoc """
  Phase 1l of the substrate cutover. Drops `product_simulations`. Rows
  move to `nodes` under `type_key: "simulation"`.

  The cross-domain `simulation_id` (pointing at the Simulation engine's
  `hydra_x_simulations` table) moves into `attributes["simulation_id"]`.
  Substrate nodes don't enforce FKs into non-substrate tables; callers
  that need to resolve it use HydraX.Simulation directly with the id.

  Per spec §12 no data preservation.
  """

  use Ecto.Migration

  def up do
    drop table(:product_simulations)
  end

  def down do
    create table(:product_simulations) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :simulation_id, :integer
      add :scenario_summary, :text
      add :archetype_summary, {:array, :map}, null: false, default: []
      add :status, :string, null: false, default: "configuring"
      add :results_imported, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}
      add :scope, :string, null: false, default: "project"
      add :scope_root_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:product_simulations, [:project_id])
    create index(:product_simulations, [:status])
    create index(:product_simulations, [:scope, :scope_root_id])
  end
end
