defmodule HydraX.Runtime.Jobs do
  @moduledoc """
  Scheduled job CRUD, job run tracking, execution, and delivery.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Repo
  alias HydraX.Workspace

  alias HydraX.Gateway.Adapters.{Discord, Slack, Telegram, Webchat}
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
    with {:ok, normalized_attrs} <-
           attrs
           |> Helpers.normalize_string_keys()
           |> apply_schedule_text(job) do
      persist_scheduled_job(job, normalized_attrs)
    end
  end

  defp persist_scheduled_job(%ScheduledJob{} = job, normalized_attrs) do
    interval_minutes =
      persisted_integer(normalized_attrs, "interval_minutes", job.interval_minutes || 60)

    run_hour = persisted_integer(normalized_attrs, "run_hour", job.run_hour)
    run_minute = persisted_integer(normalized_attrs, "run_minute", job.run_minute)
    schedule_mode = Map.get(normalized_attrs, "schedule_mode", job.schedule_mode || "interval")
    weekday_csv = persisted_weekday_csv(normalized_attrs, "weekday_csv", job.weekday_csv)
    cron_expression = Map.get(normalized_attrs, "cron_expression", job.cron_expression)

    active_hour_start =
      persisted_integer(normalized_attrs, "active_hour_start", job.active_hour_start)

    active_hour_end = persisted_integer(normalized_attrs, "active_hour_end", job.active_hour_end)

    timeout_seconds =
      persisted_integer(normalized_attrs, "timeout_seconds", job.timeout_seconds || 120)

    retry_limit = persisted_integer(normalized_attrs, "retry_limit", job.retry_limit || 0)

    retry_backoff_seconds =
      persisted_integer(
        normalized_attrs,
        "retry_backoff_seconds",
        job.retry_backoff_seconds || 0
      )

    pause_after_failures =
      persisted_integer(
        normalized_attrs,
        "pause_after_failures",
        job.pause_after_failures || 0
      )

    cooldown_minutes =
      persisted_integer(normalized_attrs, "cooldown_minutes", job.cooldown_minutes || 0)

    run_retention_days =
      persisted_integer(normalized_attrs, "run_retention_days", job.run_retention_days || 30)

    interval_minutes = interval_minutes || job.interval_minutes || 60
    timeout_seconds = timeout_seconds || job.timeout_seconds || 120
    retry_limit = retry_limit || job.retry_limit || 0
    retry_backoff_seconds = retry_backoff_seconds || job.retry_backoff_seconds || 0
    pause_after_failures = pause_after_failures || job.pause_after_failures || 0
    cooldown_minutes = cooldown_minutes || job.cooldown_minutes || 0
    run_retention_days = run_retention_days || job.run_retention_days || 30

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
      |> Map.put("active_hour_start", active_hour_start)
      |> Map.put("active_hour_end", active_hour_end)
      |> Map.put("timeout_seconds", timeout_seconds)
      |> Map.put("retry_limit", retry_limit)
      |> Map.put("retry_backoff_seconds", retry_backoff_seconds)
      |> Map.put("pause_after_failures", pause_after_failures)
      |> Map.put("cooldown_minutes", cooldown_minutes)
      |> Map.put("run_retention_days", run_retention_days)
      |> Map.put("next_run_at", next_run_at)

    retry_on_busy(fn ->
      job
      |> ScheduledJob.changeset(attrs)
      |> Repo.insert_or_update()
    end)
  end

  def delete_scheduled_job!(id) do
    job = get_scheduled_job!(id)
    Repo.delete!(job)
  end

  def reset_scheduled_job_circuit!(id) do
    job = get_scheduled_job!(id)

    {:ok, updated} =
      job
      |> ScheduledJob.changeset(%{
        circuit_state: "closed",
        consecutive_failures: 0,
        circuit_opened_at: nil,
        paused_until: nil,
        last_failure_at: nil,
        last_failure_reason: nil
      })
      |> Repo.update()

    updated
  end

  def list_due_scheduled_jobs(now) do
    ScheduledJob
    |> where(
      [job],
      job.enabled == true and not is_nil(job.next_run_at) and job.next_run_at <= ^now and
        (job.circuit_state != "open" or
           (not is_nil(job.paused_until) and job.paused_until <= ^now))
    )
    |> preload([:agent])
    |> Repo.all()
  end

  def recent_job_runs(limit_or_opts \\ 20)

  def recent_job_runs(limit) when is_integer(limit) do
    list_job_runs(limit: limit)
  end

  def recent_job_runs(opts) when is_list(opts) do
    list_job_runs(Keyword.put_new(opts, :limit, 20))
  end

  def list_job_runs(job_id_or_opts, limit \\ nil)

  def list_job_runs(job_id, limit) when is_integer(job_id) do
    query_job_runs(scheduled_job_id: job_id, limit: limit || 20)
  end

  def list_job_runs(opts, nil) when is_list(opts) do
    query_job_runs(opts)
  end

  defp query_job_runs(opts) do
    status = Keyword.get(opts, :status)
    kind = Keyword.get(opts, :kind)
    search = Keyword.get(opts, :search)
    delivery_status = Keyword.get(opts, :delivery_status)
    scheduled_job_id = Keyword.get(opts, :scheduled_job_id)
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    JobRun
    |> join(:left, [run], job in assoc(run, :scheduled_job))
    |> preload([run, job], [:agent, scheduled_job: job])
    |> maybe_filter_job_run_status(status)
    |> maybe_filter_job_run_kind(kind)
    |> maybe_filter_job_run_scheduled_job(scheduled_job_id)
    |> maybe_filter_job_run_delivery_status(delivery_status)
    |> maybe_filter_job_run_search(search)
    |> order_by([run, _job], desc: run.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def recent_job_runs_by_status(status, limit \\ 20) do
    JobRun
    |> where([run], run.status == ^status)
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload([:scheduled_job, :agent])
    |> Repo.all()
  end

  def open_circuit_jobs(limit \\ 20) do
    ScheduledJob
    |> where([job], job.circuit_state == "open")
    |> order_by([job], desc: job.updated_at, asc: job.name)
    |> limit(^limit)
    |> preload([:agent])
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
    with_job_execution_lease(job, fn ->
      now = DateTime.utc_now()
      job = refresh_job_for_execution(job, now)
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

      result = finalize_job_run(job, run, started_at)

      Phoenix.PubSub.broadcast(HydraX.PubSub, "jobs", {:job_completed, job.id})
      result
    end)
  end

  def scheduler_status do
    passes = scheduler_pass_snapshots()
    skipped_runs = recent_job_runs_by_status("skipped", 10)

    %{
      jobs: list_scheduled_jobs(limit: 50),
      runs: recent_job_runs(20),
      open_circuits: open_circuit_jobs(),
      skipped_runs: skipped_runs,
      skipped_reason_counts: summarize_skip_reasons(skipped_runs),
      lease_owned_skips: recent_lease_owned_skips(skipped_runs),
      timeout_runs: recent_job_runs_by_status("timeout", 10),
      coordination: HydraX.Runtime.coordination_status(),
      pending_ingress:
        Map.get(passes, :pending_ingress, scheduler_count_snapshot("processed_count")),
      stale_work_item_claims:
        Map.get(passes, :stale_work_item_claims, scheduler_count_snapshot("expired_count")),
      assignment_recoveries:
        Map.get(passes, :assignment_recoveries, scheduler_count_snapshot("recovered_count")),
      role_queue_dispatches:
        Map.get(passes, :role_queue_dispatches, scheduler_count_snapshot("processed_count")),
      work_item_replays:
        Map.get(passes, :work_item_replays, scheduler_count_snapshot("resumed_count")),
      ownership_handoffs:
        Map.get(passes, :ownership_handoffs, scheduler_count_snapshot("resumed_count")),
      deferred_deliveries:
        Map.get(passes, :deferred_deliveries, scheduler_count_snapshot("delivered_count")),
      delegation_expansions:
        Map.get(passes, :delegation_expansions, scheduler_count_snapshot("processed_count")),
      deferred_cooldowns:
        Map.get(passes, :deferred_cooldowns, scheduler_count_snapshot("processed_count"))
    }
  end

  def record_scheduler_pass(kind, summary)
      when kind in [
             :pending_ingress,
             :stale_work_item_claims,
             :assignment_recoveries,
             :role_queue_dispatches,
             :work_item_replays,
             :ownership_handoffs,
             :deferred_deliveries,
             :delegation_expansions,
             :deferred_cooldowns
           ] and
             is_map(summary) do
    passes =
      scheduler_pass_snapshots()
      |> Map.put(kind, summary)

    :persistent_term.put({__MODULE__, :scheduler_passes}, passes)
    :ok
  end

  def reset_scheduler_passes do
    :persistent_term.erase({__MODULE__, :scheduler_passes})
    :ok
  end

  defp scheduler_pass_snapshots,
    do: :persistent_term.get({__MODULE__, :scheduler_passes}, %{})

  defp scheduler_count_snapshot(primary_key) do
    %{
      "owner" => HydraX.Runtime.coordination_status().owner,
      primary_key => 0,
      "skipped_count" => 0,
      "error_count" => 0,
      "results" => []
    }
  end

  defp summarize_skip_reasons(runs) do
    runs
    |> Enum.map(&job_run_status_reason/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.map(fn {reason, count} -> %{reason: reason, count: count} end)
    |> Enum.sort_by(fn %{reason: reason, count: count} -> {-count, reason} end)
  end

  defp recent_lease_owned_skips(runs) do
    runs
    |> Enum.filter(&(job_run_status_reason(&1) == "lease_owned_elsewhere"))
    |> Enum.take(5)
  end

  defp job_run_status_reason(%JobRun{metadata: metadata}) when is_map(metadata) do
    metadata["status_reason"] || metadata[:status_reason]
  end

  defp job_run_status_reason(_run), do: nil

  defp with_job_execution_lease(%ScheduledJob{} = job, fun) when is_function(fun, 0) do
    if Config.repo_multi_writer?() do
      lease_name = job_execution_lease_name(job.id)

      case HydraX.Runtime.claim_lease(lease_name,
             ttl_seconds: job_execution_lease_ttl_seconds(job),
             metadata: %{
               "type" => "scheduled_job",
               "job_id" => job.id,
               "job_name" => job.name,
               "kind" => job.kind
             }
           ) do
        {:ok, lease} ->
          try do
            fun.()
          after
            _ = HydraX.Runtime.release_lease(lease_name, owner: lease.owner)
          end

        {:error, {:taken, lease}} ->
          record_job_execution_skip(job, lease)

        {:error, reason} ->
          {:error, reason}
      end
    else
      fun.()
    end
  end

  defp record_job_execution_skip(%ScheduledJob{} = job, lease) do
    now = DateTime.utc_now()
    owner = lease && lease.owner
    lease_name = job_execution_lease_name(job.id)

    Repo.insert(
      JobRun.changeset(%JobRun{}, %{
        scheduled_job_id: job.id,
        agent_id: job.agent_id,
        status: "skipped",
        started_at: now,
        finished_at: now,
        output: "Skipped #{job.name}: execution already owned by #{owner || "another node"}.",
        metadata: %{
          "status_reason" => "lease_owned_elsewhere",
          "lease_name" => lease_name,
          "lease_owner" => owner,
          "lease_expires_at" => lease && lease.expires_at
        }
      })
    )
  end

  defp job_execution_lease_name(job_id) when is_integer(job_id), do: "scheduled_job:#{job_id}"

  defp job_execution_lease_ttl_seconds(%ScheduledJob{} = job) do
    attempts = max(job.retry_limit || 0, 0) + 1
    timeout_seconds = max(job.timeout_seconds || 120, 1)
    retry_backoff_seconds = max(job.retry_backoff_seconds || 0, 0)
    attempts * timeout_seconds + max(attempts - 1, 0) * retry_backoff_seconds + 30
  end

  @doc """
  Returns aggregate statistics for recent job runs: total count,
  success/error breakdown, and average duration in milliseconds.
  """
  def job_stats(limit \\ 100) do
    runs = recent_job_runs(limit: limit)
    total = length(runs)
    successes = Enum.count(runs, &(&1.status == "success"))
    errors = Enum.count(runs, &(&1.status == "error"))
    timeouts = Enum.count(runs, &(&1.status == "timeout"))
    skipped = Enum.count(runs, &(&1.status == "skipped"))

    durations =
      runs
      |> Enum.map(fn run -> get_in(run.metadata || %{}, ["duration_ms"]) end)
      |> Enum.reject(&is_nil/1)

    avg_duration_ms =
      case durations do
        [] -> nil
        ds -> (Enum.sum(ds) / length(ds)) |> round()
      end

    %{
      total: total,
      success: successes,
      error: errors,
      timeout: timeouts,
      skipped: skipped,
      success_rate: if(total > 0, do: Float.round(successes / total * 100, 1), else: 0.0),
      avg_duration_ms: avg_duration_ms
    }
  end

  def export_job_runs(output_root, opts \\ []) when is_binary(output_root) and is_list(opts) do
    File.mkdir_p!(output_root)

    runs = list_job_runs(opts)
    base_name = "hydra-x-job-runs-#{timestamp_slug()}"
    markdown_path = Path.join(output_root, "#{base_name}.md")
    json_path = Path.join(output_root, "#{base_name}.json")
    filters = Enum.into(opts, %{})

    File.write!(markdown_path, render_job_runs_markdown(runs, filters))

    File.write!(
      json_path,
      Jason.encode_to_iodata!(render_job_runs_json(runs, filters), pretty: true)
    )

    {:ok,
     %{
       markdown_path: markdown_path,
       json_path: json_path,
       count: length(runs)
     }}
  end

  def parse_schedule_text(text) when is_binary(text) do
    normalized =
      text
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")

    cond do
      normalized == "" ->
        {:error, :blank}

      Regex.match?(~r/^cron\s+/, normalized) ->
        expression = String.replace_prefix(normalized, "cron ", "")
        parse_cron_schedule(expression)

      Regex.match?(~r/^every\s+\d+\s+minute(s)?$/, normalized) ->
        [minutes] =
          Regex.run(~r/^every\s+(\d+)\s+minute(?:s)?$/, normalized, capture: :all_but_first)

        {:ok, %{"schedule_mode" => "interval", "interval_minutes" => String.to_integer(minutes)}}

      Regex.match?(~r/^every\s+\d+\s+hour(s)?$/, normalized) ->
        [hours] = Regex.run(~r/^every\s+(\d+)\s+hour(?:s)?$/, normalized, capture: :all_but_first)

        {:ok,
         %{"schedule_mode" => "interval", "interval_minutes" => String.to_integer(hours) * 60}}

      Regex.match?(~r/^every hour$/, normalized) ->
        {:ok, %{"schedule_mode" => "interval", "interval_minutes" => 60}}

      Regex.match?(~r/^daily\s+\d{1,2}:\d{2}$/, normalized) ->
        [hour, minute] =
          Regex.run(~r/^daily\s+(\d{1,2}):(\d{2})$/, normalized, capture: :all_but_first)

        {:ok,
         %{
           "schedule_mode" => "daily",
           "run_hour" => String.to_integer(hour),
           "run_minute" => String.to_integer(minute)
         }}

      Regex.match?(~r/^weekdays\s+\d{1,2}:\d{2}$/, normalized) ->
        [hour, minute] =
          Regex.run(~r/^weekdays\s+(\d{1,2}):(\d{2})$/, normalized, capture: :all_but_first)

        {:ok,
         %{
           "schedule_mode" => "weekly",
           "weekday_csv" => "mon,tue,wed,thu,fri",
           "run_hour" => String.to_integer(hour),
           "run_minute" => String.to_integer(minute)
         }}

      Regex.match?(~r/^weekly\s+[\w,\s]+\s+\d{1,2}:\d{2}$/, normalized) ->
        [days, hour, minute] =
          Regex.run(
            ~r/^weekly\s+([\w,\s]+)\s+(\d{1,2}):(\d{2})$/,
            normalized,
            capture: :all_but_first
          )

        {:ok,
         %{
           "schedule_mode" => "weekly",
           "weekday_csv" => normalize_schedule_weekdays(days),
           "run_hour" => String.to_integer(hour),
           "run_minute" => String.to_integer(minute)
         }}

      true ->
        {:error, :unsupported}
    end
  end

  def parse_schedule_text(_), do: {:error, :unsupported}

  def schedule_text_for(%ScheduledJob{schedule_mode: "daily"} = job) do
    "daily #{pad(job.run_hour)}:#{pad(job.run_minute)}"
  end

  def schedule_text_for(%ScheduledJob{schedule_mode: "weekly"} = job) do
    days =
      case job.weekday_csv do
        "mon,tue,wed,thu,fri" -> "weekdays"
        csv -> "weekly #{csv || "mon"}"
      end

    "#{days} #{pad(job.run_hour)}:#{pad(job.run_minute)}"
  end

  def schedule_text_for(%ScheduledJob{schedule_mode: "cron"} = job) do
    "cron #{job.cron_expression || "* * * * *"}"
  end

  def schedule_text_for(%ScheduledJob{} = job) do
    minutes = job.interval_minutes || 60

    cond do
      rem(minutes, 60) == 0 and minutes >= 60 ->
        hours = div(minutes, 60)
        "every #{hours} hour#{if(hours == 1, do: "", else: "s")}"

      true ->
        "every #{minutes} minute#{if(minutes == 1, do: "", else: "s")}"
    end
  end

  # -- Job execution --

  defp refresh_job_for_execution(%ScheduledJob{} = job, now) do
    if job.circuit_state == "open" and circuit_ready?(job, now) do
      {:ok, refreshed} =
        job
        |> ScheduledJob.changeset(%{
          circuit_state: "closed",
          circuit_opened_at: nil,
          paused_until: nil
        })
        |> Repo.update()

      refreshed
    else
      job
    end
  end

  defp finalize_job_run(%ScheduledJob{} = job, %JobRun{} = run, started_at) do
    case classify_job_execution(job, started_at) do
      {:skipped, output, metadata} ->
        finished_at = DateTime.utc_now()
        Telemetry.scheduler_job(job.kind, :ok, %{status: "skipped"})

        {:ok, run} =
          run
          |> JobRun.changeset(%{
            status: "skipped",
            finished_at: finished_at,
            output: output,
            metadata: metadata
          })
          |> Repo.update()

        {:ok, run} = prune_job_run_history({:ok, run}, job)
        {:ok, run}

      {:success, output, metadata} ->
        finished_at = DateTime.utc_now()
        duration_ms = DateTime.diff(finished_at, started_at, :millisecond)
        Telemetry.scheduler_job(job.kind, :ok)
        reset_job_failure_state(job)

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
        |> prune_job_run_history(job)

      {:timeout, reason, metadata} ->
        finished_at = DateTime.utc_now()
        duration_ms = DateTime.diff(finished_at, started_at, :millisecond)
        Telemetry.scheduler_job(job.kind, :error, %{reason: inspect(reason), status: "timeout"})
        apply_job_failure_state(job, inspect(reason), finished_at)

        {:ok, run} =
          run
          |> JobRun.changeset(%{
            status: "timeout",
            finished_at: finished_at,
            output: inspect(reason),
            metadata:
              Map.merge(metadata, %{"error" => inspect(reason), "duration_ms" => duration_ms})
          })
          |> Repo.update()

        maybe_deliver_job_run(job, run)
        |> prune_job_run_history(job)

      {:error, reason, metadata} ->
        finished_at = DateTime.utc_now()
        duration_ms = DateTime.diff(finished_at, started_at, :millisecond)
        Telemetry.scheduler_job(job.kind, :error, %{reason: inspect(reason)})
        apply_job_failure_state(job, inspect(reason), finished_at)

        {:ok, run} =
          run
          |> JobRun.changeset(%{
            status: "error",
            finished_at: finished_at,
            output: inspect(reason),
            metadata:
              Map.merge(metadata, %{"error" => inspect(reason), "duration_ms" => duration_ms})
          })
          |> Repo.update()

        maybe_deliver_job_run(job, run)
        |> prune_job_run_history(job)
    end
  end

  defp classify_job_execution(%ScheduledJob{} = job, started_at) do
    cond do
      job.circuit_state == "open" ->
        {:skipped, "Skipped because the scheduler circuit is open.",
         %{
           "status_reason" => "circuit_open",
           "paused_until" => job.paused_until
         }}

      active_hours_allowed?(job, started_at) ->
        execute_scheduled_job_with_policy(job)

      true ->
        {:skipped, "Skipped outside active hours.",
         %{
           "status_reason" => "outside_active_hours",
           "active_hours" => format_active_hours(job)
         }}
    end
  end

  defp execute_scheduled_job_with_policy(%ScheduledJob{} = job) do
    attempts_allowed = max(job.retry_limit || 0, 0) + 1
    do_execute_job_attempt(job, 1, attempts_allowed)
  end

  defp do_execute_job_attempt(%ScheduledJob{} = job, attempt, attempts_allowed) do
    metadata = %{
      "attempt" => attempt,
      "attempts_allowed" => attempts_allowed,
      "timeout_seconds" => job.timeout_seconds || 120
    }

    case execute_scheduled_job_once(job) do
      {:ok, output, execution_metadata} ->
        {:success, output,
         Map.merge(execution_metadata, Map.put(metadata, "retries_used", attempt - 1))}

      {:timeout, reason} ->
        maybe_retry_job(job, attempt, attempts_allowed, reason, metadata, :timeout)

      {:error, reason} ->
        maybe_retry_job(job, attempt, attempts_allowed, reason, metadata, :error)
    end
  end

  defp maybe_retry_job(job, attempt, attempts_allowed, reason, metadata, status) do
    if attempt < attempts_allowed do
      maybe_wait_for_retry(job.retry_backoff_seconds || 0)
      do_execute_job_attempt(job, attempt + 1, attempts_allowed)
    else
      merged = Map.merge(metadata, %{"retries_used" => attempt - 1})

      case status do
        :timeout -> {:timeout, reason, merged}
        :error -> {:error, reason, merged}
      end
    end
  end

  defp execute_scheduled_job_once(%ScheduledJob{} = job) do
    task =
      Task.Supervisor.async_nolink(HydraX.TaskSupervisor, fn ->
        execute_scheduled_job(job)
      end)

    timeout_ms = max(job.timeout_seconds || 120, 1) * 1_000

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, output, metadata}} -> {:ok, output, metadata}
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, reason}
      nil -> {:timeout, :job_timeout}
    end
  end

  defp maybe_wait_for_retry(0), do: :ok

  defp maybe_wait_for_retry(seconds) when is_integer(seconds) and seconds > 0 do
    Process.sleep(min(seconds, 5) * 1_000)
  end

  defp active_hours_allowed?(
         %ScheduledJob{active_hour_start: nil, active_hour_end: nil},
         _datetime
       ),
       do: true

  defp active_hours_allowed?(%ScheduledJob{} = job, datetime) do
    hour = datetime.hour
    start_hour = job.active_hour_start || 0
    end_hour = job.active_hour_end || 0

    cond do
      start_hour == end_hour ->
        true

      start_hour < end_hour ->
        hour >= start_hour and hour < end_hour

      true ->
        hour >= start_hour or hour < end_hour
    end
  end

  defp format_active_hours(%ScheduledJob{active_hour_start: nil, active_hour_end: nil}),
    do: "always"

  defp format_active_hours(%ScheduledJob{} = job) do
    "#{pad(job.active_hour_start)}:00-#{pad(job.active_hour_end)}:00 UTC"
  end

  defp circuit_ready?(%ScheduledJob{paused_until: nil}, _now), do: false

  defp circuit_ready?(%ScheduledJob{} = job, now),
    do: DateTime.compare(job.paused_until, now) != :gt

  defp reset_job_failure_state(%ScheduledJob{} = job) do
    job
    |> ScheduledJob.changeset(%{
      consecutive_failures: 0,
      circuit_state: "closed",
      circuit_opened_at: nil,
      paused_until: nil,
      last_failure_at: nil,
      last_failure_reason: nil
    })
    |> Repo.update()
  end

  defp prune_job_run_history({:ok, %JobRun{} = run}, %ScheduledJob{} = job) do
    retention_days = job.run_retention_days || 30

    if retention_days <= 0 do
      {:ok, run}
    else
      cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

      {deleted, _} =
        JobRun
        |> where(
          [job_run],
          job_run.scheduled_job_id == ^job.id and job_run.inserted_at < ^cutoff and
            job_run.id != ^run.id
        )
        |> Repo.delete_all()

      if deleted > 0 do
        HydraX.Safety.log_event(%{
          agent_id: job.agent_id,
          category: "scheduler",
          level: "info",
          message: "Pruned scheduled job run history",
          metadata: %{
            job_id: job.id,
            job_name: job.name,
            deleted_runs: deleted,
            retention_days: retention_days
          }
        })
      end

      {:ok, run}
    end
  end

  defp apply_job_failure_state(%ScheduledJob{} = job, reason, failed_at) do
    consecutive_failures = (job.consecutive_failures || 0) + 1

    should_open? =
      (job.pause_after_failures || 0) > 0 and
        consecutive_failures >= (job.pause_after_failures || 0)

    paused_until =
      if should_open? and (job.cooldown_minutes || 0) > 0 do
        DateTime.add(failed_at, (job.cooldown_minutes || 0) * 60, :second)
      end

    attrs = %{
      consecutive_failures: consecutive_failures,
      last_failure_at: failed_at,
      last_failure_reason: reason,
      circuit_state: if(should_open?, do: "open", else: job.circuit_state || "closed"),
      circuit_opened_at: if(should_open?, do: failed_at, else: job.circuit_opened_at),
      paused_until: paused_until
    }

    {:ok, updated} =
      job
      |> ScheduledJob.changeset(attrs)
      |> Repo.update()

    if should_open? do
      HydraX.Safety.log_event(%{
        agent_id: job.agent_id,
        category: "scheduler",
        level: "warn",
        message: "Scheduler circuit opened",
        metadata: %{
          job_id: job.id,
          job_name: job.name,
          consecutive_failures: updated.consecutive_failures,
          paused_until: updated.paused_until,
          reason: reason
        }
      })
    end

    {:ok, updated}
  end

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

  defp execute_scheduled_job(%ScheduledJob{kind: "ingest"} = job) do
    with {:ok, agent} <- fetch_job_agent(job) do
      ingest_dir = Path.join(agent.workspace_root, "ingest")
      File.mkdir_p!(ingest_dir)

      files =
        ingest_dir
        |> File.ls!()
        |> Enum.map(&Path.join(ingest_dir, &1))
        |> Enum.filter(&(File.regular?(&1) and HydraX.Ingest.Parser.supported?(&1)))

      if files == [] do
        {:ok, "No supported ingest files found in #{ingest_dir}",
         %{"file_count" => 0, "created" => 0, "restored" => 0, "skipped" => 0}}
      else
        {summary, imported_files} =
          Enum.reduce(files, {%{created: 0, restored: 0, skipped: 0, archived: 0}, []}, fn file,
                                                                                           {acc,
                                                                                            names} ->
            case HydraX.Ingest.Pipeline.ingest_file(agent.id, file) do
              {:ok, result} ->
                merged = %{
                  created: acc.created + result.created,
                  restored: acc.restored + Map.get(result, :restored, 0),
                  skipped: acc.skipped + result.skipped,
                  archived: acc.archived + result.archived
                }

                {merged, [Path.basename(file) | names]}

              {:error, reason} ->
                throw({:ingest_error, Path.basename(file), reason})
            end
          end)

        output =
          "Ingested #{length(imported_files)} files: #{Enum.reverse(imported_files) |> Enum.join(", ")}"

        {:ok, output,
         %{
           "file_count" => length(imported_files),
           "files" => Enum.reverse(imported_files),
           "created" => summary.created,
           "restored" => summary.restored,
           "skipped" => summary.skipped,
           "archived" => summary.archived
         }}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  catch
    {:ingest_error, file, reason} ->
      {:error, {:ingest_failed, file, reason}}
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "maintenance"} = job) do
    with {:ok, agent} <- fetch_job_agent(job),
         deleted_runs <- delete_old_job_runs(max(job.run_retention_days || 30, 1)),
         bulletin <- HydraX.Runtime.Agents.refresh_agent_bulletin!(agent.id),
         {:ok, report} <-
           HydraX.Report.export_snapshot(Path.join(Config.install_root(), "reports")) do
      {:ok,
       "Maintenance completed for #{agent.slug}: deleted #{deleted_runs} old runs and refreshed bulletin.",
       %{
         "deleted_old_runs" => deleted_runs,
         "bulletin_memory_count" => bulletin.memory_count,
         "report_markdown_path" => report.markdown_path,
         "report_json_path" => report.json_path
       }}
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "autonomy"} = job) do
    with {:ok, agent} <- fetch_job_agent(job),
         {:ok, summary} <- HydraX.Runtime.run_autonomy_cycle(agent.id, job_id: job.id) do
      output =
        case summary.status do
          "idle" ->
            "Autonomy cycle idle for #{agent.slug}"

          "skipped" ->
            "Autonomy cycle skipped for #{agent.slug}: #{summary.reason}"

          _ ->
            "Autonomy cycle processed #{summary.processed_count} work item(s) for #{agent.slug}"
        end

      {:ok, output,
       %{
         "status" => summary.status,
         "processed_count" => summary.processed_count,
         "work_item_id" => summary[:work_item] && summary.work_item.id,
         "artifact_count" => length(summary[:artifacts] || []),
         "action" => summary[:action]
       }}
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "research"} = job) do
    with {:ok, agent} <- fetch_job_agent(job) do
      config = job.config || %{}
      mode = config["research_mode"] || "refresh_stale"

      case mode do
        "refresh_stale" ->
          execute_stale_refresh(agent, config)

        "review_findings" ->
          execute_findings_review(agent, config)

        "full_research" ->
          execute_full_research(agent, job, config)

        _ ->
          {:ok, "Unknown research mode: #{mode}", %{"mode" => mode, "status" => "skipped"}}
      end
    end
  end

  defp execute_stale_refresh(agent, config) do
    max_findings = config["max_findings_per_run"] || 10

    stale_memories =
      HydraX.Memory.list_memories(agent_id: agent.id, limit: max_findings)
      |> Enum.filter(fn entry ->
        entry.status in ["active", "durable"] and
          HydraX.Memory.Evidence.stale?(entry.metadata || %{})
      end)

    refreshed =
      Enum.reduce(stale_memories, 0, fn entry, count ->
        refreshed_metadata =
          HydraX.Memory.Evidence.mark_refreshed(entry.metadata || %{})

        case HydraX.Memory.update_memory(entry, %{metadata: refreshed_metadata}) do
          {:ok, _} -> count + 1
          _ -> count
        end
      end)

    delta = %{
      "refreshed" => refreshed,
      "stale_checked" => length(stale_memories),
      "mode" => "refresh_stale"
    }

    {:ok, "Refreshed #{refreshed}/#{length(stale_memories)} stale findings for #{agent.slug}",
     delta}
  end

  defp execute_findings_review(agent, _config) do
    promoted = HydraX.Memory.Lifecycle.promote_candidates!(agent.id)
    expired = HydraX.Memory.Lifecycle.expire_stale_memories!(agent.id)

    candidates_remaining =
      HydraX.Memory.list_memories(agent_id: agent.id, status: "candidate", limit: 200)
      |> length()

    delta = %{
      "promoted" => promoted,
      "expired" => expired,
      "candidates_remaining" => candidates_remaining,
      "mode" => "review_findings"
    }

    {:ok,
     "Promoted #{promoted}, expired #{expired}, #{candidates_remaining} candidates remaining for #{agent.slug}",
     delta}
  end

  defp execute_full_research(agent, job, config) do
    query =
      config["research_query"] || job.prompt || "Review recent findings and update knowledge."

    {:ok, work_item} =
      HydraX.Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => query,
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "status" => "planned",
        "metadata" => %{
          "task_type" => "scheduled_research",
          "scheduled_job_id" => job.id
        }
      })

    case HydraX.Runtime.run_autonomy_cycle(agent.id, work_item_id: work_item.id) do
      {:ok, summary} ->
        {:ok, "Research completed for #{agent.slug}: #{summary.status}",
         %{
           "work_item_id" => work_item.id,
           "status" => summary.status,
           "mode" => "full_research"
         }}

      {:error, reason} ->
        {:ok, "Research failed for #{agent.slug}: #{inspect(reason)}",
         %{
           "work_item_id" => work_item.id,
           "status" => "failed",
           "mode" => "full_research",
           "error" => inspect(reason)
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
        {:deferred, reason} -> {:error, reason}
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
    case delivery_allowed_by_policy?(job) do
      :ok ->
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

      {:error, reason} ->
        HydraX.Safety.log_event(%{
          agent_id: job.agent_id,
          category: "scheduler",
          level: "warn",
          message: "Scheduled job delivery blocked by policy",
          metadata: %{
            job_id: job.id,
            job_name: job.name,
            reason: inspect(reason),
            channel: job.delivery_channel,
            target: job.delivery_target
          }
        })

        update_job_run_delivery(run, %{
          "status" => "blocked",
          "channel" => job.delivery_channel,
          "target" => job.delivery_target,
          "attempted_at" => DateTime.utc_now(),
          "reason" => inspect(reason)
        })
    end
  end

  defp delivery_allowed_by_policy?(%ScheduledJob{agent_id: agent_id, delivery_channel: channel}) do
    HydraX.Runtime.authorize_delivery(agent_id, :job, channel)
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

  defp deliver_job_run(%ScheduledJob{delivery_channel: "discord", delivery_target: target}, run) do
    with config when not is_nil(config) <-
           HydraX.Runtime.DiscordAdmin.enabled_discord_config(),
         true <- is_binary(target) and target != "",
         {:ok, state} <-
           Discord.connect(%{
             "bot_token" => config.bot_token,
             "application_id" => config.application_id,
             "webhook_secret" => config.webhook_secret,
             "deliver" => Application.get_env(:hydra_x, :discord_deliver)
           }),
         {:ok, metadata} <-
           normalize_delivery_result(
             Discord.deliver(%{content: job_delivery_message(run), external_ref: target}, state)
           ) do
      {:ok,
       %{
         "status" => "delivered",
         "channel" => "discord",
         "target" => target,
         "delivered_at" => DateTime.utc_now(),
         "metadata" => stringify_metadata(metadata)
       }}
    else
      nil -> {:error, :discord_not_configured}
      false -> {:error, :missing_delivery_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_job_run(%ScheduledJob{delivery_channel: "slack", delivery_target: target}, run) do
    with config when not is_nil(config) <-
           HydraX.Runtime.SlackAdmin.enabled_slack_config(),
         true <- is_binary(target) and target != "",
         {:ok, state} <-
           Slack.connect(%{
             "bot_token" => config.bot_token,
             "signing_secret" => config.signing_secret,
             "deliver" => Application.get_env(:hydra_x, :slack_deliver)
           }),
         {:ok, metadata} <-
           normalize_delivery_result(
             Slack.deliver(%{content: job_delivery_message(run), external_ref: target}, state)
           ) do
      {:ok,
       %{
         "status" => "delivered",
         "channel" => "slack",
         "target" => target,
         "delivered_at" => DateTime.utc_now(),
         "metadata" => stringify_metadata(metadata)
       }}
    else
      nil -> {:error, :slack_not_configured}
      false -> {:error, :missing_delivery_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_job_run(%ScheduledJob{delivery_channel: "webchat", delivery_target: target}, run) do
    with config when not is_nil(config) <-
           HydraX.Runtime.WebchatAdmin.enabled_webchat_config(),
         true <- is_binary(target) and target != "",
         {:ok, state} <-
           Webchat.connect(%{
             "enabled" => config.enabled,
             "title" => config.title,
             "subtitle" => config.subtitle,
             "welcome_prompt" => config.welcome_prompt,
             "composer_placeholder" => config.composer_placeholder
           }),
         {:ok, metadata} <-
           normalize_delivery_result(
             Webchat.deliver(%{content: job_delivery_message(run), external_ref: target}, state)
           ) do
      {:ok,
       %{
         "status" => "delivered",
         "channel" => "webchat",
         "target" => target,
         "delivered_at" => DateTime.utc_now(),
         "metadata" => stringify_metadata(metadata)
       }}
    else
      nil -> {:error, :webchat_not_configured}
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
    retry_on_busy(fn ->
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
    end)
  end

  defp retry_on_busy(fun, attempts \\ 20)

  defp retry_on_busy(fun, attempts) when is_function(fun, 0) and attempts > 1 do
    fun.()
  rescue
    error ->
      if String.contains?(Exception.message(error), "Database busy") do
        Process.sleep(50)
        retry_on_busy(fun, attempts - 1)
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp retry_on_busy(fun, _attempts), do: fun.()

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

        Logger.warning(
          "Invalid cron expression #{inspect(expression)}, falling back to 1h interval"
        )

        DateTime.add(from, 3600, :second)
    end
  end

  defp apply_schedule_text(attrs, %ScheduledJob{} = _job) do
    case Helpers.blank_to_nil(Map.get(attrs, "schedule_text")) do
      nil ->
        {:ok, attrs}

      text ->
        case parse_schedule_text(text) do
          {:ok, parsed} ->
            {:ok,
             attrs
             |> Map.merge(parsed)
             |> Map.delete("schedule_text")}

          {:error, reason} ->
            {:error,
             ScheduledJob.changeset(%ScheduledJob{}, attrs)
             |> Ecto.Changeset.add_error(
               :schedule_text,
               schedule_text_error_message(reason)
             )}
        end
    end
  end

  defp schedule_text_error_message(:blank), do: "cannot be blank"
  defp schedule_text_error_message(:invalid_cron), do: "contains an invalid cron expression"
  defp schedule_text_error_message(:unsupported), do: "is not a supported schedule format"
  defp schedule_text_error_message(_), do: "is invalid"

  defp parse_cron_schedule(expression) do
    case Crontab.CronExpression.Parser.parse(expression) do
      {:ok, _} -> {:ok, %{"schedule_mode" => "cron", "cron_expression" => expression}}
      {:error, _} -> {:error, :invalid_cron}
    end
  end

  defp normalize_schedule_weekdays(days) do
    days
    |> String.replace(" ", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(fn
      "monday" -> "mon"
      "tuesday" -> "tue"
      "wednesday" -> "wed"
      "thursday" -> "thu"
      "friday" -> "fri"
      "saturday" -> "sat"
      "sunday" -> "sun"
      day -> day
    end)
    |> Enum.join(",")
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

  defp maybe_filter_job_run_status(query, nil), do: query
  defp maybe_filter_job_run_status(query, ""), do: query

  defp maybe_filter_job_run_status(query, status),
    do: where(query, [run, _job], run.status == ^status)

  defp maybe_filter_job_run_kind(query, nil), do: query
  defp maybe_filter_job_run_kind(query, ""), do: query
  defp maybe_filter_job_run_kind(query, kind), do: where(query, [_run, job], job.kind == ^kind)

  defp maybe_filter_job_run_scheduled_job(query, nil), do: query

  defp maybe_filter_job_run_scheduled_job(query, scheduled_job_id),
    do: where(query, [run, _job], run.scheduled_job_id == ^scheduled_job_id)

  defp maybe_filter_job_run_delivery_status(query, nil), do: query
  defp maybe_filter_job_run_delivery_status(query, ""), do: query

  defp maybe_filter_job_run_delivery_status(query, delivery_status) do
    where(
      query,
      [run, _job],
      fragment("?->'delivery'->>? = ?", run.metadata, "status", ^delivery_status)
    )
  end

  defp maybe_filter_job_run_search(query, nil), do: query
  defp maybe_filter_job_run_search(query, ""), do: query

  defp maybe_filter_job_run_search(query, search) do
    term = "%" <> String.downcase(search) <> "%"

    where(
      query,
      [run, job],
      like(fragment("lower(?)", run.output), ^term) or
        like(fragment("lower(?)", job.name), ^term)
    )
  end

  defp render_job_runs_markdown(runs, filters) do
    """
    # Hydra-X Job Runs

    Generated at: #{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()}
    Filters: #{inspect(filters)}

    #{Enum.map_join(runs, "\n", &render_job_run_markdown/1)}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp render_job_run_markdown(run) do
    delivery = run.metadata["delivery"] || %{}
    reason = run.metadata["status_reason"] || run.metadata["error"] || "none"

    """
    - ##{run.id} #{run.scheduled_job && run.scheduled_job.name}
      status=#{run.status}
      kind=#{run.scheduled_job && run.scheduled_job.kind}
      at=#{format_datetime(run.inserted_at)}
      delivery=#{Map.get(delivery, "status", "none")}
      reason=#{reason}
    """
    |> String.trim_trailing()
  end

  defp render_job_runs_json(runs, filters) do
    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      filters: filters,
      runs:
        Enum.map(runs, fn run ->
          %{
            id: run.id,
            status: run.status,
            output: run.output,
            inserted_at: run.inserted_at,
            started_at: run.started_at,
            finished_at: run.finished_at,
            metadata: run.metadata,
            scheduled_job:
              if(run.scheduled_job,
                do: %{
                  id: run.scheduled_job.id,
                  name: run.scheduled_job.name,
                  kind: run.scheduled_job.kind
                },
                else: nil
              )
          }
        end)
    }
  end

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp timestamp_slug do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace(":", "-")
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

  defp pad(nil), do: "00"
  defp pad(value) when value < 10, do: "0#{value}"
  defp pad(value), do: to_string(value)
end
