defmodule HydraX.Simulation.Schema.SimTick do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sim_ticks" do
    field :tick_number, :integer
    field :duration_us, :integer
    field :tier_counts, :map
    field :llm_calls, :integer
    field :tokens_used, :integer
    field :world_delta, :map

    belongs_to :simulation, HydraX.Simulation.Schema.Simulation

    timestamps()
  end

  def changeset(tick, attrs) do
    tick
    |> cast(attrs, [
      :simulation_id,
      :tick_number,
      :duration_us,
      :tier_counts,
      :llm_calls,
      :tokens_used,
      :world_delta
    ])
    |> validate_required([:simulation_id, :tick_number])
  end
end
