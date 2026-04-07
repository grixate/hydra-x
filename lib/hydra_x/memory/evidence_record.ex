defmodule HydraX.Memory.EvidenceRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_memory_evidence" do
    field :product_node_type, :string
    field :product_node_id, :integer
    field :source_kind, :string
    field :source_ref, :string
    field :excerpt, :string
    field :speaker_role, :string
    field :occurred_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :memory, HydraX.Memory.Entry

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :memory_id,
      :product_node_type,
      :product_node_id,
      :source_kind,
      :source_ref,
      :excerpt,
      :speaker_role,
      :occurred_at,
      :metadata
    ])
    |> validate_required([:source_kind, :excerpt])
    |> foreign_key_constraint(:memory_id)
  end
end
