defmodule HydraX.Product.StreamEntry do
  @moduledoc """
  Persisted Stream entry generated from terminal `AgentTask` transitions per
  Command Center spec §8. Complements the derived Stream view.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @tabs ~w(activity needs_you blockers)
  @context_types ~w(node source session flow task)

  schema "stream_entries" do
    field :tab, :string
    field :source_agent_id, :string
    field :title, :string
    field :summary, :string
    field :context_type, :string
    field :context_id, :integer
    field :read_at, :utc_datetime_usec
    field :actioned_at, :utc_datetime_usec

    belongs_to :project, HydraX.Product.Project
    belongs_to :source_task, HydraX.Product.AgentTask

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def tabs, do: @tabs

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :project_id,
      :tab,
      :source_task_id,
      :source_agent_id,
      :title,
      :summary,
      :context_type,
      :context_id,
      :read_at,
      :actioned_at
    ])
    |> validate_required([:project_id, :tab, :title])
    |> validate_inclusion(:tab, @tabs)
    |> validate_inclusion(:context_type, @context_types, message: "is not a valid context type")
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:source_task_id)
  end
end
