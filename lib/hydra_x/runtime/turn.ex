defmodule HydraX.Runtime.Turn do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_turns" do
    field :sequence, :integer
    field :role, :string
    field :kind, :string, default: "message"
    field :content, :string
    field :metadata, :map, default: %{}
    field :branch_id, Ecto.UUID

    belongs_to :conversation, HydraX.Runtime.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [:conversation_id, :sequence, :role, :kind, :content, :metadata, :branch_id])
    |> validate_required([:conversation_id, :sequence, :role, :kind, :content, :branch_id])
    |> assoc_constraint(:conversation)
    |> unique_constraint([:conversation_id, :branch_id, :sequence])
  end
end
