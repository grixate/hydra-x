defmodule HydraX.Runtime.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :channel, :string, default: "cli"
    field :external_ref, :string
    field :status, :string, default: "active"
    field :title, :string
    field :last_message_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile
    has_many :turns, HydraX.Runtime.Turn
    has_many :checkpoints, HydraX.Runtime.Checkpoint

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :agent_id,
      :channel,
      :external_ref,
      :status,
      :title,
      :last_message_at,
      :metadata
    ])
    |> validate_required([:agent_id, :channel, :status])
    |> assoc_constraint(:agent)
  end
end
