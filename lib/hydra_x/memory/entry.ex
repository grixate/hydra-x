defmodule HydraX.Memory.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(Fact Preference Decision Identity Event Observation Goal Todo)
  @statuses ~w(active superseded merged archived)

  schema "memory_entries" do
    field :type, :string
    field :status, :string, default: "active"
    field :content, :string
    field :importance, :float, default: 0.5
    field :metadata, :map, default: %{}
    field :last_seen_at, :utc_datetime_usec

    belongs_to :agent, HydraX.Runtime.AgentProfile
    belongs_to :conversation, HydraX.Runtime.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :agent_id,
      :conversation_id,
      :type,
      :status,
      :content,
      :importance,
      :metadata,
      :last_seen_at
    ])
    |> validate_required([:agent_id, :type, :content])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:importance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> assoc_constraint(:agent)
    |> assoc_constraint(:conversation)
  end
end
