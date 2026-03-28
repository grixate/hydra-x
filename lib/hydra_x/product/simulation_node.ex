defmodule HydraX.Product.SimulationNode do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(configuring running completed failed)

  schema "product_simulations" do
    field :scenario_summary, :string
    field :archetype_summary, {:array, :map}, default: []
    field :status, :string, default: "configuring"
    field :results_imported, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    belongs_to :simulation, HydraX.Simulation.Schema.Simulation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:project_id, :simulation_id, :scenario_summary, :archetype_summary, :status, :results_imported, :metadata])
    |> validate_required([:project_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:simulation_id)
  end
end
