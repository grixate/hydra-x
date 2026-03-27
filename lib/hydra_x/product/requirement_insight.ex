defmodule HydraX.Product.RequirementInsight do
  use Ecto.Schema
  import Ecto.Changeset

  schema "requirement_insights" do
    field :metadata, :map, default: %{}

    belongs_to :requirement, HydraX.Product.Requirement
    belongs_to :insight, HydraX.Product.Insight

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:requirement_id, :insight_id, :metadata])
    |> validate_required([:requirement_id, :insight_id])
    |> foreign_key_constraint(:requirement_id)
    |> foreign_key_constraint(:insight_id)
    |> unique_constraint([:requirement_id, :insight_id])
  end
end
