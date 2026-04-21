defmodule HydraX.Product.Flow do
  @moduledoc """
  A derived grouping of related `AgentTask`s linked via `Mention`s. Spec §6
  of the task-data-model.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(ongoing complete stalled cancelled)

  schema "flows" do
    field :name, :string
    field :status, :string, default: "ongoing"
    field :participating_agent_ids, {:array, :string}, default: []
    field :task_ids, {:array, :integer}, default: []
    field :completed_at, :utc_datetime_usec

    belongs_to :project, HydraX.Product.Project
    belongs_to :originating_task, HydraX.Product.AgentTask, foreign_key: :originating_task_id

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :project_id,
      :name,
      :originating_task_id,
      :status,
      :participating_agent_ids,
      :task_ids,
      :completed_at
    ])
    |> validate_required([:project_id, :name, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:originating_task_id)
  end
end
