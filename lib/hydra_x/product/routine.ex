defmodule HydraX.Product.Routine do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active paused archived)
  @schedule_types ~w(cron event)
  @output_targets ~w(graph_node stream_item)

  schema "routines" do
    field :title, :string
    field :description, :string
    field :prompt_template, :string
    field :assigned_persona, :string
    field :schedule_type, :string, default: "cron"
    field :cron_expression, :string
    field :event_trigger, :string
    field :timezone, :string, default: "UTC"
    field :output_target, :string, default: "stream_item"
    field :status, :string, default: "active"
    field :last_run_at, :utc_datetime
    field :last_run_status, :string
    field :last_run_tokens, :integer
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    has_many :routine_runs, HydraX.Product.RoutineRun

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(routine, attrs) do
    routine
    |> cast(attrs, [
      :project_id, :title, :description, :prompt_template, :assigned_persona,
      :schedule_type, :cron_expression, :event_trigger, :timezone, :output_target,
      :status, :last_run_at, :last_run_status, :last_run_tokens, :metadata
    ])
    |> validate_required([:project_id, :title, :prompt_template, :assigned_persona, :schedule_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:schedule_type, @schedule_types)
    |> validate_inclusion(:output_target, @output_targets)
    |> foreign_key_constraint(:project_id)
  end
end
