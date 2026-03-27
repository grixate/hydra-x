defmodule HydraX.Product.SourceChunk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "source_chunks" do
    field :ordinal, :integer
    field :content, :string
    field :token_count, :integer
    field :metadata, :map, default: %{}
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :project, HydraX.Product.Project
    belongs_to :source, HydraX.Product.Source

    has_many :insight_evidence, HydraX.Product.InsightEvidence

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :project_id,
      :source_id,
      :ordinal,
      :content,
      :token_count,
      :metadata,
      :embedding
    ])
    |> validate_required([:project_id, :source_id, :ordinal, :content])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:source_id)
    |> unique_constraint([:source_id, :ordinal])
  end
end
