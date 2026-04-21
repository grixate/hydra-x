defmodule HydraX.Runtime.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_conversations" do
    field :channel, :string, default: "cli"
    field :external_ref, :string
    field :status, :string, default: "active"
    field :title, :string
    field :last_message_at, :utc_datetime_usec
    field :metadata, :map, default: %{}
    field :active_branch_id, Ecto.UUID

    belongs_to :agent, HydraX.Runtime.AgentProfile
    has_many :turns, HydraX.Runtime.Turn
    has_many :hx_turns, HydraX.Runtime.Turn, foreign_key: :conversation_id
    has_many :checkpoints, HydraX.Runtime.Checkpoint
    has_many :branches, HydraX.Runtime.ConversationBranch

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
      :metadata,
      :active_branch_id
    ])
    |> validate_required([:agent_id, :channel, :status])
    |> assoc_constraint(:agent)
  end
end
