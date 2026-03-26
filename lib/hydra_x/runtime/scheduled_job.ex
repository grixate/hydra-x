defmodule HydraX.Runtime.ScheduledJob do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(heartbeat prompt backup ingest maintenance autonomy research)
  @schedule_modes ~w(interval daily weekly cron)
  @circuit_states ~w(closed open)

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
    field :active_hour_start, :integer
    field :active_hour_end, :integer
    field :timeout_seconds, :integer, default: 120
    field :retry_limit, :integer, default: 0
    field :retry_backoff_seconds, :integer, default: 0
    field :pause_after_failures, :integer, default: 0
    field :cooldown_minutes, :integer, default: 0
    field :run_retention_days, :integer, default: 30
    field :consecutive_failures, :integer, default: 0
    field :circuit_state, :string, default: "closed"
    field :circuit_opened_at, :utc_datetime_usec
    field :paused_until, :utc_datetime_usec
    field :last_failure_at, :utc_datetime_usec
    field :last_failure_reason, :string
    field :next_run_at, :utc_datetime_usec
    field :last_run_at, :utc_datetime_usec
    field :cron_expression, :string
    field :schedule_text, :string, virtual: true
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
      :cron_expression,
      :schedule_text,
      :enabled,
      :delivery_enabled,
      :delivery_channel,
      :delivery_target,
      :active_hour_start,
      :active_hour_end,
      :timeout_seconds,
      :retry_limit,
      :retry_backoff_seconds,
      :pause_after_failures,
      :cooldown_minutes,
      :run_retention_days,
      :consecutive_failures,
      :circuit_state,
      :circuit_opened_at,
      :paused_until,
      :last_failure_at,
      :last_failure_reason,
      :next_run_at,
      :last_run_at,
      :config
    ])
    |> validate_required([:agent_id, :name, :kind, :schedule_mode])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:schedule_mode, @schedule_modes)
    |> validate_inclusion(:circuit_state, @circuit_states)
    |> validate_schedule()
    |> validate_delivery()
    |> validate_execution_policy()
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
        |> validate_weekday_csv()
        |> validate_number(:run_hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
        |> validate_number(:run_minute, greater_than_or_equal_to: 0, less_than_or_equal_to: 59)

      "cron" ->
        changeset
        |> validate_required([:cron_expression])
        |> validate_cron_expression()

      _ ->
        changeset
        |> validate_required([:interval_minutes])
        |> validate_number(:interval_minutes, greater_than: 0)
    end
  end

  defp validate_cron_expression(changeset) do
    case get_field(changeset, :cron_expression) do
      nil ->
        changeset

      expression ->
        case Crontab.CronExpression.Parser.parse(expression) do
          {:ok, _} -> changeset
          {:error, _} -> add_error(changeset, :cron_expression, "is not a valid cron expression")
        end
    end
  end

  defp validate_weekday_csv(changeset) do
    allowed = MapSet.new(~w(mon tue wed thu fri sat sun))

    case get_field(changeset, :weekday_csv) do
      nil ->
        changeset

      csv ->
        tokens =
          csv
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        if tokens != [] and Enum.all?(tokens, &MapSet.member?(allowed, &1)) do
          changeset
        else
          add_error(changeset, :weekday_csv, "must use weekdays like mon,tue,wed")
        end
    end
  end

  defp validate_delivery(changeset) do
    if get_field(changeset, :delivery_enabled) do
      changeset
      |> validate_required([:delivery_channel, :delivery_target])
      |> validate_inclusion(:delivery_channel, ["telegram", "discord", "slack", "webchat"])
    else
      changeset
    end
  end

  defp validate_execution_policy(changeset) do
    changeset
    |> validate_number(:active_hour_start, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_number(:active_hour_end, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_number(:timeout_seconds, greater_than: 0, less_than_or_equal_to: 86_400)
    |> validate_number(:retry_limit, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:retry_backoff_seconds,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 86_400
    )
    |> validate_number(:pause_after_failures,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:cooldown_minutes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 43_200
    )
    |> validate_number(:run_retention_days,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 3650
    )
    |> validate_number(:consecutive_failures, greater_than_or_equal_to: 0)
    |> validate_active_hours()
  end

  defp validate_active_hours(changeset) do
    start_hour = get_field(changeset, :active_hour_start)
    end_hour = get_field(changeset, :active_hour_end)

    if is_nil(start_hour) == is_nil(end_hour) do
      changeset
    else
      add_error(changeset, :active_hour_start, "requires both start and end hours")
    end
  end
end
