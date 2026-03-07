defmodule HydraX.Runtime.ScheduledJob do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(heartbeat prompt backup)
  @schedule_modes ~w(interval daily weekly)

  schema "scheduled_jobs" do
    field :name, :string
    field :kind, :string, default: "heartbeat"
    field :prompt, :string
    field :schedule_mode, :string, default: "interval"
    field :interval_minutes, :integer, default: 60
    field :weekday_csv, :string
    field :run_hour, :integer
    field :run_minute, :integer
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
      :schedule_mode,
      :interval_minutes,
      :weekday_csv,
      :run_hour,
      :run_minute,
      :enabled,
      :delivery_enabled,
      :delivery_channel,
      :delivery_target,
      :next_run_at,
      :last_run_at,
      :config
    ])
    |> validate_required([:agent_id, :name, :kind, :schedule_mode])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:schedule_mode, @schedule_modes)
    |> validate_schedule()
    |> validate_delivery()
    |> assoc_constraint(:agent)
  end

  defp validate_schedule(changeset) do
    case get_field(changeset, :schedule_mode) do
      "daily" ->
        changeset
        |> validate_required([:run_hour, :run_minute])
        |> validate_number(:run_hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
        |> validate_number(:run_minute, greater_than_or_equal_to: 0, less_than_or_equal_to: 59)

      "weekly" ->
        changeset
        |> validate_required([:weekday_csv, :run_hour, :run_minute])
        |> validate_number(:run_hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
        |> validate_number(:run_minute, greater_than_or_equal_to: 0, less_than_or_equal_to: 59)

      _ ->
        changeset
        |> validate_required([:interval_minutes])
        |> validate_number(:interval_minutes, greater_than: 0)
    end
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
