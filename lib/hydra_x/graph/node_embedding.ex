defmodule HydraX.Graph.NodeEmbedding do
  @moduledoc """
  Vector embedding for a node, stored in a separate table so the core
  `nodes` row stays lean and so multiple embedding models can coexist.
  The substrate keeps embeddings out of the critical write path — a
  node write should never have to touch pgvector.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Node

  schema "node_embeddings" do
    field :embedding_model, :string
    field :embedding, Pgvector.Ecto.Vector
    field :embedded_at, :utc_datetime_usec

    belongs_to :node, Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node_embedding, attrs) do
    node_embedding
    |> cast(attrs, [:node_id, :embedding_model, :embedding, :embedded_at])
    |> validate_required([:node_id, :embedding_model, :embedding, :embedded_at])
    |> unique_constraint([:node_id, :embedding_model])
    |> foreign_key_constraint(:node_id)
  end
end
