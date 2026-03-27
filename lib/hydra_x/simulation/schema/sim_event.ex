defmodule HydraX.Simulation.Schema.SimEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sim_events" do
    field :tick, :integer
    field :event_type, :string
    field :source, :string
    field :target, :string
    field :description, :string
    field :properties, :map, default: %{}
    field :stakes, :float

    belongs_to :simulation, HydraX.Simulation.Schema.Simulation

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :simulation_id,
      :tick,
      :event_type,
      :source,
      :target,
      :description,
      :properties,
      :stakes
    ])
    |> validate_required([:simulation_id, :tick, :event_type])
  end
end
