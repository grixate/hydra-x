defmodule HydraX.Simulation.Schema.Simulation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "simulations" do
    field :name, :string
    field :status, :string, default: "configuring"
    field :config, :map
    field :seed_material, :string
    field :world_snapshot, :map
    field :total_ticks, :integer, default: 0
    field :total_llm_calls, :integer, default: 0
    field :total_tokens_used, :integer, default: 0
    field :total_cost_cents, :integer, default: 0
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :agent, HydraX.Runtime.AgentProfile

    has_many :sim_agent_profiles, HydraX.Simulation.Schema.SimAgentProfile
    has_many :sim_events, HydraX.Simulation.Schema.SimEvent
    has_many :sim_ticks, HydraX.Simulation.Schema.SimTick
    has_many :sim_reports, HydraX.Simulation.Schema.SimReport

    timestamps()
  end

  @required_fields [:name, :config]
  @optional_fields [
    :status,
    :seed_material,
    :world_snapshot,
    :total_ticks,
    :total_llm_calls,
    :total_tokens_used,
    :total_cost_cents,
    :started_at,
    :completed_at,
    :agent_id
  ]

  def changeset(simulation, attrs) do
    simulation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(configuring seeding running paused completed failed))
  end
end
