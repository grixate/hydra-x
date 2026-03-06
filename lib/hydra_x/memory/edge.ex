defmodule HydraX.Memory.Edge do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(relates_to contradicts supersedes supports part_of)

  schema "memory_edges" do
    field :kind, :string
    field :weight, :float, default: 1.0
    field :metadata, :map, default: %{}

    belongs_to :from_memory, HydraX.Memory.Entry
    belongs_to :to_memory, HydraX.Memory.Entry

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:from_memory_id, :to_memory_id, :kind, :weight, :metadata])
    |> validate_required([:from_memory_id, :to_memory_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:weight, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:from_memory_id)
    |> foreign_key_constraint(:to_memory_id)
  end
end
