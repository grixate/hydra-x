defmodule HydraX.Runtime.Jobs do
  @moduledoc """
  Scheduled job CRUD, job run tracking, execution, and delivery.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Repo
  alias HydraX.Workspace

  alias HydraX.Gateway.Adapters.Telegram
  alias HydraX.Telemetry

  alias HydraX.Runtime.{
    AgentProfile,
    Helpers,
    JobRun,
    ScheduledJob
  }

  def list_scheduled_jobs(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    kind = Keyword.get(opts, :kind)
    enabled = Keyword.get(opts, :enabled)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    ScheduledJob
    |> preload([:agent])
    |> maybe_filter_scheduled_job_agent(agent_id)
    |> maybe_filter_scheduled_job_kind(kind)
    |> maybe_filter_scheduled_job_enabled(enabled)
    |> maybe_filter_scheduled_job_search(search)
    |> order_by([job], asc: job.next_run_at, asc: job.name)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def get_scheduled_job!(id) do
    ScheduledJob
    |> Repo.get!(id)
    |> Repo.preload([:agent])
  end

  def change_scheduled_job(job \\ %ScheduledJob{}, attrs \\ %{}) do
    ScheduledJob.changeset(job, attrs)
  end

  def save_scheduled_job(attrs) when is_map(attrs),
    do: save_scheduled_job(%ScheduledJob{}, attrs)

  def save_scheduled_job(%ScheduledJob{} = job, attrs) do
    normalized_attrs = Helpers.normalize_string_keys(attrs)

    interval_minutes =
      persisted_integer(normalized_attrs, "interval_minutes", job.interval_minutes || 60)

    run_hour = persisted_integer(normalized_attrs, "run_hour", job.run_hour)
    run_minute = persisted_integer(normalized_attrs, "run_minute", job.run_minute)
    schedule_mode = Map.get(normalized_attrs, "schedule_mode", job.schedule_mode || "interval")
    weekday_csv = persisted_weekday_csv(normalized_attrs, "weekday_csv", job.weekday_csv)
    cron_expression = Map.get(normalized_attrs, "cron_expression", job.cron_expression)

    interval_minutes = interval_minutes || job.interval_minutes || 60

    next_run_at =
      case Helpers.blank_to_nil(Map.get(normalized_attrs, "next_run_at")) do
        nil ->
          next_run_at(%ScheduledJob{
            job
            | schedule_mode: schedule_mode,
              interval_minutes: interval_minutes || job.interval_minutes,
              weekday_csv: weekday_csv,
              cron_expression: cron_expression,
              run_hour: run_hour || job.run_hour,
              run_minute: run_minute || job.run_minute
          })

        value ->
          value
      end

    attrs =
      normalized_attrs
      |> Map.put("schedule_mode", schedule_mode)
      |> Map.put("interval_minutes", interval_minutes)
      |> Map.put("weekday_csv", weekday_csv)
      |> Map.put("cron_expression", cron_expression)
      |> Map.put("run_hour", run_hour)
      |> Map.put("run_minute", run_minute)
      |> Map.put("next_run_at", next_run_at)

    job
    |> ScheduledJob.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def delete_scheduled_job!(id) do
    job = get_scheduled_job!(id)
    Repo.delete!(job)
  end

  def list_due_scheduled_jobs(now) do
    ScheduledJob
    |> where(
      [job],
      job.enabled == true and not is_nil(job.next_run_at) and job.next_run_at <= ^now
    )
    |> preload([:agent])
    |> Repo.all()
  end

  def recent_job_runs(limit \\ 20) do
    JobRun
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload([:scheduled_job, :agent])
    |> Repo.all()
  end

  def list_job_runs(job_id, limit \\ 20) do
    JobRun
    |> where([run], run.scheduled_job_id == ^job_id)
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload([:scheduled_job, :agent])
    |> Repo.all()
  end

  def delete_old_job_runs(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days * 86_400, :second)

    {count, _} =
      JobRun
      |> where([run], run.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  def ensure_heartbeat_job!(agent_id) do
    ensure_named_job!(agent_id, "heartbeat", "Workspace heartbeat", %{
      interval_minutes: 60,
      enabled: true
    })
  end

  def ensure_backup_job!(agent_id) do
    ensure_named_job!(agent_id, "backup", "Portable backup bundle", %{
      interval_minutes: 1_440,
      enabled: true
    })
  end

  def ensure_default_jobs! do
    case HydraX.Runtime.Agents.get_default_agent() do
      nil ->
        []

      agent ->
        [
          ensure_heartbeat_job!(agent.id),
          ensure_backup_job!(agent.id)
        ]
    end
  end

  def run_scheduled_job(%ScheduledJob{} = job) do
    started_at = DateTime.utc_now()

    {:ok, %{job: job, run: run}} =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :job,
        ScheduledJob.changeset(job, %{
          last_run_at: started_at,
          next_run_at: next_run_at(job, started_at)
        })
      )
      |> Ecto.Multi.insert(
        :run,
        JobRun.changeset(%JobRun{}, %{
          scheduled_job_id: job.id,
          agent_id: job.agent_id,
          status: "running",
          started_at: started_at
        })
      )
      |> Repo.transaction()

    result =
      case execute_scheduled_job(job) do
        {:ok, output, metadata} ->
          finished_at = DateTime.utc_now()
          duration_ms = DateTime.diff(finished_at, started_at, :millisecond)
          Telemetry.scheduler_job(job.kind, :ok)

          {:ok, run} =
            run
            |> JobRun.changeset(%{
              status: "success",
              finished_at: finished_at,
              output: output,
              metadata: Map.merge(metadata, %{"duration_ms" => duration_ms})
            })
            |> Repo.update()

          maybe_deliver_job_run(job, run)

        {:error, reason} ->
          finished_at = DateTime.utc_now()
          duration_ms = DateTime.diff(finished_at, started_at, :millisecond)
          Telemetry.scheduler_job(job.kind, :error, %{reason: inspect(reason)})

          {:ok, run} =
            run
            |> JobRun.changeset(%{
              status: "error",
              finished_at: finished_at,
              output: inspect(reason),
              metadata: %{"error" => inspect(reason), "duration_ms" => duration_ms}
            })
            |> Repo.update()

          maybe_deliver_job_run(job, run)
      end

    Phoenix.PubSub.broadcast(HydraX.PubSub, "jobs", {:job_completed, job.id})
    result
  end

  def scheduler_status do
    %{
      jobs: list_scheduled_jobs(limit: 50),
      runs: recent_job_runs(20)
    }
  end

  @doc """
  Returns aggregate statistics for recent job runs: total count,
  success/error breakdown, and average duration in milliseconds.
  """
  def job_stats(limit \\ 100) do
    runs = recent_job_runs(limit)
    total = length(runs)
    successes = Enum.count(runs, &(&1.status == "success"))
    errors = Enum.count(runs, &(&1.status == "error"))

    durations =
      runs
      |> Enum.map(fn run -> get_in(run.metadata || %{}, ["duration_ms"]) end)
      |> Enum.reject(&is_nil/1)

    avg_duration_ms =
      case durations do
        [] -> nil
        ds -> Enum.sum(ds) / length(ds) |> round()
      end

    %{
      total: total,
      success: successes,
      error: errors,
      success_rate: if(total > 0, do: Float.round(successes / total * 100, 1), else: 0.0),
      avg_duration_ms: avg_duration_ms
    }
  end

  # -- Job execution --

  defp execute_scheduled_job(%ScheduledJob{kind: "heartbeat"} = job) do
    with {:ok, agent} <- fetch_job_agent(job),
         heartbeat <- Workspace.load_context(agent.workspace_root)["HEARTBEAT.md"] || "" do
      prompt =
        [
          job.prompt ||
            "Run the heartbeat routine for this workspace and report anything that needs operator attention.",
          heartbeat
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")

      run_job_prompt(agent, job, prompt)
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "prompt"} = job) do
    with {:ok, agent} <- fetch_job_agent(job) do
      run_job_prompt(agent, job, job.prompt || "Scheduled prompt job.")
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "backup"} = _job) do
    with {:ok, manifest} <- HydraX.Backup.create_bundle(Config.backup_root()) do
      {:ok, "Created backup bundle at #{manifest["archive_path"]}",
       %{
         "archive_path" => manifest["archive_path"],
         "manifest_path" => manifest["manifest_path"],
         "entry_count" => manifest["entry_count"]
       }}
    end
  end

  defp run_job_prompt(agent, job, prompt) do
    with {:ok, _pid} <- HydraX.Agent.ensure_started(agent),
         {:ok, conversation} <-
           HydraX.Runtime.Conversations.start_conversation(agent, %{
             channel: "scheduler",
             title: "#{job.name} #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")}",
             metadata: %{"scheduled_job_id" => job.id, "kind" => job.kind}
           }) do
      output =
        try do
          HydraX.Agent.Channel.submit(
            agent,
            conversation,
            prompt,
            %{source: "scheduler", scheduled_job_id: job.id}
          )
        rescue
          error -> {:error, Exception.message(error)}
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end

      case output do
        {:error, reason} -> {:error, reason}
        text -> {:ok, text, %{"conversation_id" => conversation.id}}
      end
    end
  end

  defp fetch_job_agent(job) do
    case Repo.get(AgentProfile, job.agent_id) do
      nil -> {:error, :agent_not_found}
      agent -> {:ok, agent}
    end
  end

  # -- Delivery --

  defp maybe_deliver_job_run(%ScheduledJob{delivery_enabled: false}, run), do: {:ok, run}
  defp maybe_deliver_job_run(%ScheduledJob{delivery_enabled: nil}, run), do: {:ok, run}

  defp maybe_deliver_job_run(%ScheduledJob{} = job, %JobRun{} = run) do
    case deliver_job_run(job, run) do
      {:ok, delivery} ->
        update_job_run_delivery(run, delivery)

      {:error, reason} ->
        HydraX.Safety.log_event(%{
          agent_id: job.agent_id,
          category: "scheduler",
          level: "error",
          message: "Scheduled job delivery failed",
          metadata: %{
            job_id: job.id,
            job_name: job.name,
            reason: inspect(reason),
            channel: job.delivery_channel,
            target: job.delivery_target
          }
        })

        update_job_run_delivery(run, %{
          "status" => "failed",
          "channel" => job.delivery_channel,
          "target" => job.delivery_target,
          "attempted_at" => DateTime.utc_now(),
          "reason" => inspect(reason)
        })
    end
  end

  defp deliver_job_run(
         %ScheduledJob{delivery_channel: "telegram", delivery_target: target},
         run
       ) do
    with config when not is_nil(config) <-
           HydraX.Runtime.TelegramAdmin.enabled_telegram_config(),
         true <- is_binary(target) and target != "",
         {:ok, state} <-
           Telegram.connect(%{
             "bot_token" => config.bot_token,
             "bot_username" => config.bot_username,
             "webhook_secret" => config.webhook_secret,
             "deliver" => Application.get_env(:hydra_x, :telegram_deliver)
           }),
         {:ok, metadata} <-
           normalize_delivery_result(
             Telegram.send_response(
               %{content: job_delivery_message(run), external_ref: target},
               state
             )
           ) do
      {:ok,
       %{
         "status" => "delivered",
         "channel" => "telegram",
         "target" => target,
         "delivered_at" => DateTime.utc_now(),
         "metadata" => stringify_metadata(metadata)
       }}
    else
      nil -> {:error, :telegram_not_configured}
      false -> {:error, :missing_delivery_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_job_run(%ScheduledJob{delivery_channel: channel}, _run) do
    {:error, {:unsupported_delivery_channel, channel}}
  end

  defp normalize_delivery_result(:ok), do: {:ok, %{}}
  defp normalize_delivery_result({:ok, metadata}) when is_map(metadata), do: {:ok, metadata}
  defp normalize_delivery_result({:error, reason}), do: {:error, reason}

  defp update_job_run_delivery(run, delivery) do
    metadata =
      (run.metadata || %{})
      |> Map.put("delivery", delivery)

    run
    |> JobRun.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  defp job_delivery_message(run) do
    """
    Hydra-X scheduled job #{run.scheduled_job_id} finished with #{run.status}.

    #{run.output || "No output captured."}
    """
    |> String.trim()
  end

  defp stringify_metadata(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  # -- Scheduling --

  defp ensure_named_job!(agent_id, kind, name, attrs) do
    jobs =
      ScheduledJob
      |> where([job], job.agent_id == ^agent_id and job.kind == ^kind and job.name == ^name)
      |> order_by([job], asc: job.inserted_at, asc: job.id)
      |> Repo.all()

    case jobs do
      [] ->
        {:ok, job} =
          save_scheduled_job(
            Map.merge(attrs, %{
              agent_id: agent_id,
              name: name,
              kind: kind
            })
          )

        job

      [job | rest] ->
        Enum.each(rest, &Repo.delete!/1)

        {:ok, job} =
          save_scheduled_job(job, %{
            interval_minutes: attrs[:interval_minutes],
            enabled: attrs[:enabled]
          })

        job
    end
  end

  defp next_run_at(%ScheduledJob{} = job), do: next_run_at(job, DateTime.utc_now())

  defp next_run_at(%ScheduledJob{schedule_mode: "daily"} = job, from) do
    next_daily_run_at(job.run_hour, job.run_minute, from)
  end

  defp next_run_at(%ScheduledJob{schedule_mode: "weekly"} = job, from) do
    next_weekly_run_at(job.weekday_csv, job.run_hour, job.run_minute, from)
  end

  defp next_run_at(%ScheduledJob{schedule_mode: "cron"} = job, from) do
    next_cron_run_at(job.cron_expression, from)
  end

  defp next_run_at(%ScheduledJob{} = job, from) do
    next_interval_run_at(job.interval_minutes || 60, from)
  end

  defp next_interval_run_at(interval_minutes, from) do
    DateTime.add(from, interval_minutes * 60, :second)
  end

  defp next_cron_run_at(expression, from) do
    case Crontab.CronExpression.Parser.parse(expression) do
      {:ok, cron} ->
        naive = DateTime.to_naive(from)

        case Crontab.Scheduler.get_next_run_date(cron, naive) do
          {:ok, next_naive} -> DateTime.from_naive!(next_naive, "Etc/UTC")
          {:error, _} -> DateTime.add(from, 3600, :second)
        end

      {:error, _} ->
        require Logger
        Logger.warning("Invalid cron expression #{inspect(expression)}, falling back to 1h interval")
        DateTime.add(from, 3600, :second)
    end
  end

  defp next_daily_run_at(run_hour, run_minute, from) do
    time = Time.new!(run_hour || 0, run_minute || 0, 0)
    date = DateTime.to_date(from)
    {:ok, naive} = NaiveDateTime.new(date, time)
    candidate = DateTime.from_naive!(naive, "Etc/UTC")

    if DateTime.compare(candidate, from) == :gt do
      candidate
    else
      {:ok, next_naive} = NaiveDateTime.new(Date.add(date, 1), time)
      DateTime.from_naive!(next_naive, "Etc/UTC")
    end
  end

  defp next_weekly_run_at(weekday_csv, run_hour, run_minute, from) do
    weekdays = parse_weekdays(weekday_csv)
    current_date = DateTime.to_date(from)

    candidates =
      0..7
      |> Enum.map(fn offset ->
        date = Date.add(current_date, offset)

        if Date.day_of_week(date) in weekdays do
          {:ok, naive} = NaiveDateTime.new(date, Time.new!(run_hour || 0, run_minute || 0, 0))
          DateTime.from_naive!(naive, "Etc/UTC")
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(DateTime.compare(&1, from) == :gt))

    List.first(candidates) ||
      next_weekly_run_at(
        weekday_csv,
        run_hour,
        run_minute,
        DateTime.add(from, 7 * 86_400, :second)
      )
  end

  defp parse_weekdays(nil), do: [1]
  defp parse_weekdays(""), do: [1]

  defp parse_weekdays(csv) do
    weekday_map = %{
      "mon" => 1,
      "tue" => 2,
      "wed" => 3,
      "thu" => 4,
      "fri" => 5,
      "sat" => 6,
      "sun" => 7
    }

    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&Map.get(weekday_map, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [1]
      weekdays -> weekdays
    end
  end

  # -- Filter helpers --

  defp maybe_filter_scheduled_job_agent(query, nil), do: query

  defp maybe_filter_scheduled_job_agent(query, agent_id),
    do: where(query, [job], job.agent_id == ^agent_id)

  defp maybe_filter_scheduled_job_kind(query, nil), do: query
  defp maybe_filter_scheduled_job_kind(query, ""), do: query
  defp maybe_filter_scheduled_job_kind(query, kind), do: where(query, [job], job.kind == ^kind)

  defp maybe_filter_scheduled_job_enabled(query, nil), do: query

  defp maybe_filter_scheduled_job_enabled(query, enabled) when is_boolean(enabled),
    do: where(query, [job], job.enabled == ^enabled)

  defp maybe_filter_scheduled_job_enabled(query, ""), do: query

  defp maybe_filter_scheduled_job_search(query, nil), do: query
  defp maybe_filter_scheduled_job_search(query, ""), do: query

  defp maybe_filter_scheduled_job_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [job],
      like(job.name, ^pattern) or like(job.prompt, ^pattern)
    )
  end

  # -- Numeric helpers --

  defp normalize_integer(nil), do: nil
  defp normalize_integer(""), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp persisted_integer(attrs, key, fallback) do
    if Map.has_key?(attrs, key) do
      normalize_integer(Map.get(attrs, key))
    else
      fallback
    end
  end

  defp normalize_weekday_csv(nil), do: nil
  defp normalize_weekday_csv(""), do: nil

  defp normalize_weekday_csv(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp persisted_weekday_csv(attrs, key, fallback) do
    if Map.has_key?(attrs, key) do
      normalize_weekday_csv(Map.get(attrs, key))
    else
      fallback
    end
  end
end
