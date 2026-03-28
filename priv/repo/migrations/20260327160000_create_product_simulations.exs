defmodule HydraX.Repo.Migrations.CreateProductSimulations do
  use Ecto.Migration

  def change do
    create table(:product_simulations) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :simulation_id, references(:simulations, on_delete: :nilify_all)
      add :scenario_summary, :text
      add :archetype_summary, :jsonb, default: "[]"
      add :status, :string, null: false, default: "configuring"
      add :results_imported, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:product_simulations, [:project_id])
    create index(:product_simulations, [:simulation_id])
    create index(:product_simulations, [:status])
  end
end
