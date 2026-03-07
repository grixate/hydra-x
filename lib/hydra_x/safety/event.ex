defmodule HydraX.Safety.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @levels ~w(info warn error)
  @statuses ~w(open acknowledged resolved)

  schema "safety_events" do
    field :category, :string
    field :level, :string
    field :message, :string
    field :metadata, :map, default: %{}
    field :status, :string, default: "open"
    field :acknowledged_at, :utc_datetime_usec
    field :acknowledged_by, :string
    field :resolved_at, :utc_datetime_usec
    field :resolved_by, :string
    field :operator_note, :string

    belongs_to :agent, HydraX.Runtime.AgentProfile
    belongs_to :conversation, HydraX.Runtime.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :agent_id,
      :conversation_id,
      :category,
      :level,
      :message,
      :metadata,
      :status,
      :acknowledged_at,
      :acknowledged_by,
      :resolved_at,
      :resolved_by,
      :operator_note
    ])
    |> validate_required([:agent_id, :category, :level, :message, :status])
    |> validate_inclusion(:level, @levels)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:agent)
    |> assoc_constraint(:conversation)
  end
end
