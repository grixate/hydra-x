defmodule HydraX.Product.TaskEvent do
  @moduledoc """
  Append-only audit log entry for an `HydraX.Product.AgentTask`. Drives
  activity history, Stream entry generation, and debugging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @event_types ~w(
    created
    state_changed
    progress_updated
    mention_emitted
    mention_received
    redirected
    proposal_partially_reviewed
    failed
  )

  @actor_types ~w(user agent system)

  schema "task_events" do
    field :event_type, :string
    field :payload, :map, default: %{}
    field :actor_type, :string
    field :actor_id, :string

    belongs_to :task, HydraX.Product.AgentTask
    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def event_types, do: @event_types

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:task_id, :project_id, :event_type, :payload, :actor_type, :actor_id])
    |> validate_required([:task_id, :project_id, :event_type, :actor_type])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:actor_type, @actor_types)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:project_id)
  end
end
