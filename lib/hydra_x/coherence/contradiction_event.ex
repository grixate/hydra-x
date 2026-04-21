defmodule HydraX.Coherence.ContradictionEvent do
  @moduledoc "Append-only audit log per `coherence-spec.md` §4."

  use Ecto.Schema
  import Ecto.Changeset

  @event_types ~w(detected re_confirmed under_review resolved dismissed re_detected stale acknowledged_tension)
  @actor_types ~w(user agent system)

  schema "contradiction_events" do
    field :event_type, :string
    field :payload, :map, default: %{}
    field :actor_type, :string
    field :actor_id, :string

    belongs_to :contradiction, HydraX.Coherence.Contradiction

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def event_types, do: @event_types

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:contradiction_id, :event_type, :payload, :actor_type, :actor_id])
    |> validate_required([:contradiction_id, :event_type, :actor_type])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:actor_type, @actor_types)
    |> foreign_key_constraint(:contradiction_id)
  end
end
