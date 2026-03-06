defmodule HydraX.Runtime.JobRun do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(running success error)

  schema "job_runs" do
    field :status, :string, default: "running"
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :output, :string
    field :metadata, :map, default: %{}

    belongs_to :scheduled_job, HydraX.Runtime.ScheduledJob
    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(job_run, attrs) do
    job_run
    |> cast(attrs, [
      :scheduled_job_id,
      :agent_id,
      :status,
      :started_at,
      :finished_at,
      :output,
      :metadata
    ])
    |> validate_required([:scheduled_job_id, :agent_id, :status, :started_at])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:scheduled_job)
    |> assoc_constraint(:agent)
  end
end
