defmodule HydraX.Repo.Migrations.CreateSimulationTables do
  use Ecto.Migration

  def change do
    create table(:simulations) do
      add :name, :string, null: false
      add :status, :string, default: "configuring"
      add :config, :map, null: false
      add :seed_material, :text
      add :world_snapshot, :map
      add :total_ticks, :integer, default: 0
      add :total_llm_calls, :integer, default: 0
      add :total_tokens_used, :integer, default: 0
      add :total_cost_cents, :integer, default: 0
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :agent_id, references(:hx_agent_profiles, on_delete: :nilify_all)
      timestamps()
    end

    create table(:sim_agent_profiles) do
      add :simulation_id, references(:simulations, on_delete: :delete_all), null: false
      add :agent_key, :string, null: false
      add :persona, :map, null: false
      add :initial_beliefs, :map, default: %{}
      add :initial_relationships, :map, default: %{}
      add :final_state, :map
      timestamps()
    end

    create table(:sim_events) do
      add :simulation_id, references(:simulations, on_delete: :delete_all), null: false
      add :tick, :integer, null: false
      add :event_type, :string, null: false
      add :source, :string
      add :target, :string
      add :description, :text
      add :properties, :map, default: %{}
      add :stakes, :float
      timestamps()
    end

    create table(:sim_ticks) do
      add :simulation_id, references(:simulations, on_delete: :delete_all), null: false
      add :tick_number, :integer, null: false
      add :duration_us, :integer
      add :tier_counts, :map
      add :llm_calls, :integer
      add :tokens_used, :integer
      add :world_delta, :map
      timestamps()
    end

    create table(:sim_reports) do
      add :simulation_id, references(:simulations, on_delete: :delete_all), null: false
      add :content, :text, null: false
      add :statistical_summary, :map
      add :generated_at, :utc_datetime
      timestamps()
    end

    create index(:sim_agent_profiles, [:simulation_id])
    create index(:sim_events, [:simulation_id, :tick])
    create index(:sim_ticks, [:simulation_id, :tick_number])
    create index(:sim_reports, [:simulation_id])
  end
end
