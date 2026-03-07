defmodule HydraX.Runtime.ScheduledJob do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(heartbeat prompt backup)

  schema "scheduled_jobs" do
    field :name, :string
    field :kind, :string, default: "heartbeat"
    field :prompt, :string
    field :interval_minutes, :integer, default: 60
    field :enabled, :boolean, default: true
    field :delivery_enabled, :boolean, default: false
    field :delivery_channel, :string
    field :delivery_target, :string
    field :next_run_at, :utc_datetime_usec
    field :last_run_at, :utc_datetime_usec
    field :config, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile
    has_many :job_runs, HydraX.Runtime.JobRun

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :agent_id,
      :name,
      :kind,
      :prompt,
      :interval_minutes,
      :enabled,
      :delivery_enabled,
      :delivery_channel,
      :delivery_target,
      :next_run_at,
      :last_run_at,
      :config
    ])
    |> validate_required([:agent_id, :name, :kind, :interval_minutes])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:interval_minutes, greater_than: 0)
    |> validate_delivery()
    |> assoc_constraint(:agent)
  end

  defp validate_delivery(changeset) do
    if get_field(changeset, :delivery_enabled) do
      changeset
      |> validate_required([:delivery_channel, :delivery_target])
      |> validate_inclusion(:delivery_channel, ["telegram"])
    else
      changeset
    end
  end
end
