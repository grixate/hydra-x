defmodule HydraX.Product.InsightEvidence do
  use Ecto.Schema
  import Ecto.Changeset

  schema "insight_evidence" do
    field :quote, :string
    field :metadata, :map, default: %{}

    belongs_to :insight, HydraX.Product.Insight
    belongs_to :source_chunk, HydraX.Product.SourceChunk

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(evidence, attrs) do
    evidence
    |> cast(attrs, [:insight_id, :source_chunk_id, :quote, :metadata])
    |> validate_required([:insight_id, :source_chunk_id])
    |> foreign_key_constraint(:insight_id)
    |> foreign_key_constraint(:source_chunk_id)
    |> unique_constraint([:insight_id, :source_chunk_id])
  end
end
