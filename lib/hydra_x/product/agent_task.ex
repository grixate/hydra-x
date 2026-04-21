defmodule HydraX.Product.AgentTask do
  @moduledoc """
  A unit of agent work within a project. Powers the Command Center surface
  (Zones 1–4) and its lifecycle drives Stream entries on terminal transitions.

  Distinct from `HydraX.Product.Task`, which models human-assigned work.
  See `docs/specs/command-center-spec.md` and `task-data-model-spec.md` for
  the full data model and state machine.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(pending running paused waiting_for_input blocked proposing completed rejected cancelled failed)
  @priorities ~w(low normal high urgent)
  @assigned_by ~w(user agent system)
  @context_types ~w(node board_session library_source flow)

  @terminal_states ~w(completed rejected cancelled failed)

  schema "agent_tasks" do
    field :agent_id, :string
    field :title, :string
    field :description, :string
    field :state, :string, default: "pending"
    field :state_reason, :string
    field :priority, :string, default: "normal"

    field :progress_current, :integer
    field :progress_total, :integer
    field :progress_label, :string

    field :context_type, :string
    field :context_id, :integer

    field :assigned_by, :string, default: "user"
    field :assigned_by_user_id, :integer
    field :assigned_by_agent_id, :string

    field :proposal_payload, :map
    field :result_payload, :map
    field :error_payload, :map

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :last_state_change_at, :utc_datetime_usec

    field :lock_version, :integer, default: 1

    field :deferred_until, :utc_datetime_usec

    belongs_to :project, HydraX.Product.Project
    belongs_to :parent_task, __MODULE__, foreign_key: :parent_task_id
    belongs_to :flow, HydraX.Product.Flow
    belongs_to :originating_mention, HydraX.Product.Mention

    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states
  def terminal_states, do: @terminal_states
  def priorities, do: @priorities

  @doc """
  Changeset for state-machine transitions. Applies `optimistic_lock` on
  `:lock_version` so concurrent transitions on the same task are serialised —
  the second writer gets a stale-entry error instead of silently clobbering.
  """
  def transition_changeset(task, attrs) do
    task
    |> changeset(attrs)
    |> optimistic_lock(:lock_version)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :lock_version,
      :project_id,
      :agent_id,
      :title,
      :description,
      :state,
      :state_reason,
      :priority,
      :progress_current,
      :progress_total,
      :progress_label,
      :context_type,
      :context_id,
      :parent_task_id,
      :flow_id,
      :originating_mention_id,
      :assigned_by,
      :assigned_by_user_id,
      :assigned_by_agent_id,
      :proposal_payload,
      :result_payload,
      :error_payload,
      :started_at,
      :completed_at,
      :last_state_change_at,
      :deferred_until
    ])
    |> validate_required([:project_id, :agent_id, :title, :state, :priority, :assigned_by])
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:assigned_by, @assigned_by)
    |> validate_inclusion(:context_type, @context_types, message: "is not a valid context type")
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:parent_task_id)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:originating_mention_id)
  end
end
