defmodule HydraX.Report do
  @moduledoc """
  Builds and exports operator-facing runtime reports.
  """

  alias HydraX.Config
  alias HydraX.Runtime

  def snapshot(opts \\ []) do
    agent = Runtime.get_default_agent() || Runtime.ensure_default_agent!()

    filters = %{
      health_status: warn_status(opts),
      readiness_status: warn_status(opts),
      search: Keyword.get(opts, :search),
      required_only: Keyword.get(opts, :required_only, false),
      safety_limit: Keyword.get(opts, :safety_limit, 20),
      job_limit: Keyword.get(opts, :job_limit, 10),
      conversation_limit: Keyword.get(opts, :conversation_limit, 10)
    }

    %{
      generated_at: now_iso8601(),
      filters: filters,
      install: Runtime.install_snapshot(),
      health_checks:
        Runtime.health_snapshot(status: filters.health_status, search: filters.search),
      readiness:
        Runtime.readiness_report(
          status: filters.readiness_status,
          search: filters.search,
          required_only: filters.required_only
        ),
      telegram: Runtime.telegram_status(),
      operator: Runtime.operator_status(),
      tools: Runtime.tool_status(),
      scheduler: scheduler_snapshot(filters.job_limit),
      observability: Runtime.observability_status(),
      safety: Runtime.safety_status(limit: filters.safety_limit),
      memory: Runtime.memory_triage_status(agent),
      budget: Runtime.budget_status(agent),
      default_agent: %{
        id: agent.id,
        name: agent.name,
        slug: agent.slug,
        status: agent.status,
        runtime: Runtime.agent_runtime_status(agent),
        bulletin: Runtime.agent_bulletin(agent.id)
      },
      conversations: Runtime.list_conversations(limit: filters.conversation_limit)
    }
  end

  def export_snapshot(), do: export_snapshot(default_output_root(), [])

  def export_snapshot(output_root) when is_binary(output_root),
    do: export_snapshot(output_root, [])

  def export_snapshot(output_root, opts) when is_binary(output_root) and is_list(opts) do
    File.mkdir_p!(output_root)

    snapshot = snapshot(opts)
    base_name = "hydra-x-report-#{timestamp_slug()}"
    markdown_path = Path.join(output_root, "#{base_name}.md")
    json_path = Path.join(output_root, "#{base_name}.json")

    File.write!(markdown_path, render_markdown(snapshot))
    File.write!(json_path, Jason.encode_to_iodata!(json_snapshot(snapshot), pretty: true))

    {:ok,
     %{
       snapshot: snapshot,
       markdown_path: markdown_path,
       json_path: json_path
     }}
  end

  def render_markdown(snapshot) do
    """
    # Hydra-X Operator Report

    Generated at: #{snapshot.generated_at}
    Public URL: #{snapshot.install.public_url}
    Default agent: #{snapshot.default_agent.name} (#{snapshot.default_agent.slug})
    Default agent runtime: #{runtime_label(snapshot.default_agent.runtime.running)}
    Workspace root: #{snapshot.install.workspace_root}
    Database path: #{snapshot.install.database_path}
    Backup root: #{snapshot.install.backup_root}

    ## Filters
    - Search: #{snapshot.filters.search || "none"}
    - Warn only: #{if(snapshot.filters.health_status == :warn, do: "yes", else: "no")}
    - Required readiness only: #{if(snapshot.filters.required_only, do: "yes", else: "no")}

    ## Health Checks
    #{render_health_checks(snapshot.health_checks)}

    ## Readiness
    Summary: #{String.upcase(Atom.to_string(snapshot.readiness.summary))}
    #{render_readiness(snapshot.readiness.items)}

    ## Default Agent
    - Status: #{snapshot.default_agent.status}
    - Runtime: #{runtime_label(snapshot.default_agent.runtime.running)}
    - Last started at: #{format_datetime(snapshot.default_agent.runtime.last_started_at)}
    - Bulletin updated at: #{format_datetime(snapshot.default_agent.bulletin.updated_at)}
    - Bulletin memory count: #{snapshot.default_agent.bulletin.memory_count}

    #{render_bulletin(snapshot.default_agent.bulletin.content)}

    ## Budget
    #{render_budget(snapshot.budget)}

    ## Memory Triage
    #{render_memory_triage(snapshot.memory)}

    ## Telegram
    - Configured: #{yes_no(snapshot.telegram.configured)}
    - Enabled: #{yes_no(snapshot.telegram.enabled)}
    - Binding: #{telegram_binding(snapshot.telegram)}
    - Webhook URL: #{snapshot.telegram.webhook_url}
    - Registered at: #{format_datetime(snapshot.telegram.registered_at)}
    - Last checked at: #{format_datetime(snapshot.telegram.last_checked_at)}
    - Pending updates: #{snapshot.telegram.pending_update_count}
    - Retryable failed deliveries: #{snapshot.telegram.retryable_count}
    - Last error: #{snapshot.telegram.last_error || "none"}
    - Recent failed conversations:
    #{render_telegram_failures(snapshot.telegram.recent_failures)}

    ## Tool Policy
    - Workspace guard: #{yes_no(snapshot.tools.workspace_guard)}
    - URL guard: #{yes_no(snapshot.tools.url_guard)}
    - Shell enabled: #{yes_no(snapshot.tools.shell_command_enabled)}
    - Shell allowlist: #{Enum.join(snapshot.tools.shell_allowlist, ", ")}
    - HTTP allowlist: #{render_http_allowlist(snapshot.tools.http_allowlist)}

    ## Scheduler
    - Configured jobs: #{length(snapshot.scheduler.jobs)}
    - Recent runs: #{length(snapshot.scheduler.runs)}

    ### Jobs
    #{render_jobs(snapshot.scheduler.jobs)}

    ### Recent Runs
    #{render_job_runs(snapshot.scheduler.runs)}

    ## Conversations
    #{render_conversations(snapshot.conversations)}

    ## Observability
    #{render_observability_summary(snapshot.observability.telemetry_summary)}

    ### Recent Telemetry Events
    #{render_recent_telemetry_events(snapshot.observability.telemetry.recent_events)}

    - OTP alarms: #{render_alarms(snapshot.observability.system.alarms)}

    ## Backup Inventory
    #{render_backups(snapshot.observability.backups.recent_backups)}

    ## Safety
    - Errors: #{snapshot.safety.counts.error}
    - Warnings: #{snapshot.safety.counts.warn}
    - Info: #{snapshot.safety.counts.info}
    - Status counts: open=#{snapshot.safety.statuses.open}, acknowledged=#{snapshot.safety.statuses.acknowledged}, resolved=#{snapshot.safety.statuses.resolved}

    ### Recent Safety Events
    #{render_safety_events(snapshot.safety.recent_events)}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp scheduler_snapshot(limit) do
    status = Runtime.scheduler_status()

    %{
      jobs: Enum.take(status.jobs, limit),
      runs: Enum.take(status.runs, limit)
    }
  end

  defp render_health_checks([]), do: "- none"

  defp render_health_checks(checks) do
    Enum.map_join(checks, "\n", fn check ->
      "- [#{String.upcase(Atom.to_string(check.status))}] #{check.name}: #{check.detail}"
    end)
  end

  defp render_readiness([]), do: "- none"

  defp render_readiness(items) do
    Enum.map_join(items, "\n", fn item ->
      requirement = if item.required, do: "required", else: "recommended"

      "- [#{String.upcase(Atom.to_string(item.status))}] #{item.label} (#{requirement}): #{item.detail}"
    end)
  end

  defp render_bulletin(nil), do: "No bulletin generated."
  defp render_bulletin(""), do: "No bulletin generated."

  defp render_bulletin(content) do
    """
    ### Bulletin
    #{content}
    """
  end

  defp render_budget(%{policy: nil}), do: "- No budget policy configured"

  defp render_budget(%{policy: policy, usage: usage, recent_usage: recent_usage}) do
    """
    - Daily limit: #{policy.daily_limit}
    - Conversation limit: #{policy.conversation_limit}
    - Hard limit action: #{policy.hard_limit_action}
    - Daily usage: #{usage.daily_tokens}
    - Conversation usage: #{usage.conversation_tokens}
    - Recent usage entries: #{length(recent_usage)}
    """
    |> String.trim()
  end

  defp render_memory_triage(%{counts: counts, recent_conflicts: recent_conflicts}) do
    """
    - Active: #{Map.get(counts, "active", 0)}
    - Conflicted: #{Map.get(counts, "conflicted", 0)}
    - Superseded: #{Map.get(counts, "superseded", 0)}
    - Merged: #{Map.get(counts, "merged", 0)}
    - Recent conflicted entries:
    #{render_conflicted_memories(recent_conflicts)}
    """
    |> String.trim()
  end

  defp render_jobs([]), do: "- none"

  defp render_jobs(jobs) do
    Enum.map_join(jobs, "\n", fn job ->
      enabled = if job.enabled, do: "enabled", else: "paused"
      "- ##{job.id} #{job.name} (#{job.kind}, #{enabled}, #{schedule_summary(job)})"
    end)
  end

  defp render_job_runs([]), do: "- none"

  defp render_job_runs(runs) do
    Enum.map_join(runs, "\n", fn run ->
      "- ##{run.id} job=#{run.scheduled_job_id} status=#{run.status} started=#{format_datetime(run.started_at)} delivery=#{render_delivery_status(run)}"
    end)
  end

  defp render_conversations([]), do: "- none"

  defp render_conversations(conversations) do
    Enum.map_join(conversations, "\n", fn conversation ->
      "- ##{conversation.id} #{conversation.channel}/#{conversation.status}: #{conversation.title || conversation.external_ref || "untitled"}"
    end)
  end

  defp render_backups([]), do: "- none"

  defp render_backups(backups) do
    Enum.map_join(backups, "\n", fn backup ->
      status = if backup["archive_exists"], do: "present", else: "missing"

      "- #{backup["archive_path"]} (archive=#{status}, entries=#{backup["entry_count"]}, created=#{backup["created_at"]})"
    end)
  end

  defp render_observability_summary(summary) do
    [
      render_observability_line("Provider", summary.provider),
      render_observability_line("Budget", summary.budget),
      render_observability_line("Tool", summary.tool),
      render_observability_line("Gateway", summary.gateway),
      render_observability_line("Scheduler", summary.scheduler)
    ]
    |> Enum.join("\n")
  end

  defp render_observability_line(label, data) do
    "- #{label}: total=#{data.total} ok=#{data.success} warn=#{data.warn} error=#{data.error} unknown=#{data.unknown}"
  end

  defp render_recent_telemetry_events([]), do: "- none"

  defp render_recent_telemetry_events(events) do
    Enum.map_join(events, "\n", fn event ->
      "- #{event.namespace}/#{event.bucket} status=#{event.status} observed=#{format_datetime(event.observed_at)}"
    end)
  end

  defp render_telegram_failures([]), do: "- none"

  defp render_telegram_failures(failures) do
    Enum.map_join(failures, "\n", fn failure ->
      "- ##{failure.id} #{failure.title} retry=#{failure.retry_count} updated=#{format_datetime(failure.updated_at)} reason=#{failure.reason || "unknown"}"
    end)
  end

  defp render_safety_events([]), do: "- none"

  defp render_safety_events(events) do
    Enum.map_join(events, "\n", fn event ->
      "- [#{String.upcase(event.level)}] #{event.category}/#{event.status}: #{event.message}"
    end)
  end

  defp render_conflicted_memories([]), do: "- none"

  defp render_conflicted_memories(memories) do
    Enum.map_join(memories, "\n", fn memory ->
      "- ##{memory.id} #{memory.type}: #{memory.content}"
    end)
  end

  defp render_alarms([]), do: "none"
  defp render_alarms(alarms), do: Enum.join(alarms, ", ")

  defp render_http_allowlist([]), do: "public hosts"
  defp render_http_allowlist(hosts), do: Enum.join(hosts, ", ")

  defp telegram_binding(%{bot_username: username, default_agent_name: agent_name})
       when is_binary(username) and username != "" and is_binary(agent_name),
       do: "@#{username} -> #{agent_name}"

  defp telegram_binding(%{default_agent_name: agent_name}) when is_binary(agent_name),
    do: agent_name

  defp telegram_binding(_), do: "unconfigured"

  defp render_delivery_status(%{metadata: %{"delivery" => %{"status" => status}}}), do: status
  defp render_delivery_status(_run), do: "n/a"

  defp schedule_summary(%{schedule_mode: "daily"} = job) do
    "daily @ #{pad2(job.run_hour || 0)}:#{pad2(job.run_minute || 0)} UTC"
  end

  defp schedule_summary(%{schedule_mode: "weekly"} = job) do
    weekdays = job.weekday_csv || "unspecified"
    hour = job.run_hour || 0
    minute = job.run_minute || 0
    "#{weekdays} @ #{pad2(hour)}:#{pad2(minute)} UTC"
  end

  defp schedule_summary(job) do
    "every #{job.interval_minutes || 0}m"
  end

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
      _ -> value
    end
  end

  defp yes_no(true), do: "yes"
  defp yes_no(_), do: "no"

  defp runtime_label(true), do: "up"
  defp runtime_label(_), do: "down"

  defp warn_status(opts) do
    if Keyword.get(opts, :only_warn, false), do: :warn, else: nil
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp timestamp_slug do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d-%H%M%S")
  end

  defp pad2(value) when is_integer(value) and value < 10, do: "0#{value}"
  defp pad2(value), do: to_string(value)

  defp default_output_root do
    Path.join(Config.install_root(), "reports")
  end

  defp json_snapshot(snapshot) do
    %{
      generated_at: snapshot.generated_at,
      filters: snapshot.filters,
      install: snapshot.install,
      health_checks: snapshot.health_checks,
      readiness: snapshot.readiness,
      telegram: snapshot.telegram,
      operator: snapshot.operator,
      tools: snapshot.tools,
      scheduler: %{
        jobs: Enum.map(snapshot.scheduler.jobs, &json_job/1),
        runs: Enum.map(snapshot.scheduler.runs, &json_job_run/1)
      },
      observability: %{
        telemetry: snapshot.observability.telemetry,
        scheduler: %{
          total_jobs: snapshot.observability.scheduler.total_jobs,
          recent_runs: Enum.map(snapshot.observability.scheduler.recent_runs, &json_job_run/1)
        },
        system: snapshot.observability.system,
        backups: snapshot.observability.backups
      },
      safety: %{
        counts: snapshot.safety.counts,
        statuses: snapshot.safety.statuses,
        categories: snapshot.safety.categories,
        recent_events: Enum.map(snapshot.safety.recent_events, &json_safety_event/1)
      },
      memory: %{
        agent_id: snapshot.memory.agent_id,
        agent_name: snapshot.memory.agent_name,
        counts: snapshot.memory.counts,
        recent_conflicts: Enum.map(snapshot.memory.recent_conflicts, &json_memory/1)
      },
      budget: json_budget(snapshot.budget),
      default_agent: %{
        id: snapshot.default_agent.id,
        name: snapshot.default_agent.name,
        slug: snapshot.default_agent.slug,
        status: snapshot.default_agent.status,
        runtime: snapshot.default_agent.runtime,
        bulletin: %{
          content: snapshot.default_agent.bulletin.content,
          updated_at: snapshot.default_agent.bulletin.updated_at,
          memory_count: snapshot.default_agent.bulletin.memory_count
        }
      },
      conversations: Enum.map(snapshot.conversations, &json_conversation/1)
    }
  end

  defp json_budget(%{policy: nil} = budget), do: Map.put(budget, :safety_events, [])

  defp json_budget(budget) do
    %{
      agent_name: budget.agent_name,
      agent_id: budget.agent_id,
      policy:
        budget.policy &&
          %{
            id: budget.policy.id,
            daily_limit: budget.policy.daily_limit,
            conversation_limit: budget.policy.conversation_limit,
            soft_warning_at: budget.policy.soft_warning_at,
            hard_limit_action: budget.policy.hard_limit_action,
            enabled: budget.policy.enabled
          },
      usage: budget.usage,
      recent_usage:
        Enum.map(budget.recent_usage, fn usage ->
          %{
            id: usage.id,
            scope: usage.scope,
            tokens_in: usage.tokens_in,
            tokens_out: usage.tokens_out,
            inserted_at: usage.inserted_at,
            conversation_id: usage.conversation_id,
            metadata: usage.metadata
          }
        end),
      safety_events: Enum.map(budget.safety_events, &json_safety_event/1)
    }
  end

  defp json_job(job) do
    %{
      id: job.id,
      name: job.name,
      kind: job.kind,
      schedule_mode: job.schedule_mode,
      interval_minutes: job.interval_minutes,
      weekday_csv: job.weekday_csv,
      run_hour: job.run_hour,
      run_minute: job.run_minute,
      enabled: job.enabled,
      delivery_enabled: job.delivery_enabled,
      delivery_channel: job.delivery_channel,
      delivery_target: job.delivery_target,
      next_run_at: job.next_run_at,
      last_run_at: job.last_run_at,
      agent_id: job.agent_id
    }
  end

  defp json_job_run(run) do
    %{
      id: run.id,
      scheduled_job_id: run.scheduled_job_id,
      agent_id: run.agent_id,
      status: run.status,
      started_at: run.started_at,
      finished_at: run.finished_at,
      output: run.output,
      metadata: run.metadata
    }
  end

  defp json_safety_event(event) do
    %{
      id: event.id,
      level: event.level,
      status: event.status,
      category: event.category,
      message: event.message,
      metadata: event.metadata,
      inserted_at: event.inserted_at,
      resolved_at: event.resolved_at,
      acknowledged_at: event.acknowledged_at,
      agent_id: event.agent_id,
      conversation_id: event.conversation_id
    }
  end

  defp json_conversation(conversation) do
    %{
      id: conversation.id,
      agent_id: conversation.agent_id,
      channel: conversation.channel,
      status: conversation.status,
      title: conversation.title,
      external_ref: conversation.external_ref,
      metadata: conversation.metadata,
      last_message_at: conversation.last_message_at,
      inserted_at: conversation.inserted_at,
      updated_at: conversation.updated_at
    }
  end

  defp json_memory(memory) do
    %{
      id: memory.id,
      agent_id: memory.agent_id,
      conversation_id: memory.conversation_id,
      type: memory.type,
      status: memory.status,
      content: memory.content,
      importance: memory.importance,
      metadata: memory.metadata,
      last_seen_at: memory.last_seen_at,
      inserted_at: memory.inserted_at,
      updated_at: memory.updated_at
    }
  end
end
