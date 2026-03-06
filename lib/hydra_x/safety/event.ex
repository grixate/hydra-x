defmodule HydraX.Safety.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @levels ~w(info warn error)

  schema "safety_events" do
    field :category, :string
    field :level, :string
    field :message, :string
    field :metadata, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile
    belongs_to :conversation, HydraX.Runtime.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:agent_id, :conversation_id, :category, :level, :message, :metadata])
    |> validate_required([:agent_id, :category, :level, :message])
    |> validate_inclusion(:level, @levels)
    |> assoc_constraint(:agent)
    |> assoc_constraint(:conversation)
  end
end
