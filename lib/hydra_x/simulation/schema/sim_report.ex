defmodule HydraX.Simulation.Schema.SimReport do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sim_reports" do
    field :content, :string
    field :statistical_summary, :map
    field :generated_at, :utc_datetime

    belongs_to :simulation, HydraX.Simulation.Schema.Simulation

    timestamps()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:simulation_id, :content, :statistical_summary, :generated_at])
    |> validate_required([:simulation_id, :content])
  end
end
