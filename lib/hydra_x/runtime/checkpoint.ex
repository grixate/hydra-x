defmodule HydraX.Runtime.Checkpoint do
  use Ecto.Schema
  import Ecto.Changeset

  schema "checkpoints" do
    field :process_type, :string
    field :state, :map, default: %{}

    belongs_to :conversation, HydraX.Runtime.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [:conversation_id, :process_type, :state])
    |> validate_required([:conversation_id, :process_type, :state])
    |> assoc_constraint(:conversation)
    |> unique_constraint([:conversation_id, :process_type])
  end
end
