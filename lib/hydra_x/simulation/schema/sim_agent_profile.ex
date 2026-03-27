defmodule HydraX.Simulation.Schema.SimAgentProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sim_agent_profiles" do
    field :agent_key, :string
    field :persona, :map
    field :initial_beliefs, :map, default: %{}
    field :initial_relationships, :map, default: %{}
    field :final_state, :map

    belongs_to :simulation, HydraX.Simulation.Schema.Simulation

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :simulation_id,
      :agent_key,
      :persona,
      :initial_beliefs,
      :initial_relationships,
      :final_state
    ])
    |> validate_required([:simulation_id, :agent_key, :persona])
  end
end
