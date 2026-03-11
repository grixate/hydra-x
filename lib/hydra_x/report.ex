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
      incident_limit: Keyword.get(opts, :incident_limit, 20),
      audit_limit: Keyword.get(opts, :audit_limit, 30),
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
      provider: Runtime.provider_status(),
      cluster: Runtime.cluster_status(),
      mcp: Runtime.mcp_statuses(),
      agent_mcp: Runtime.agent_mcp_statuses(),
      channels: Runtime.channel_statuses(),
      telegram: Runtime.telegram_status(),
      operator: Runtime.operator_status(),
      secrets: Runtime.secret_storage_status(),
      tools: Runtime.tool_status(),
      scheduler: scheduler_snapshot(filters.job_limit),
      ingest: Runtime.list_ingest_runs(agent.id, 10),
      observability: Runtime.observability_status(),
      safety: Runtime.safety_status(limit: filters.safety_limit),
      incidents: incident_snapshot(filters.incident_limit),
      audit: audit_snapshot(filters.audit_limit),
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
      agents: agent_snapshots(),
      skills: Runtime.list_skills(),
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
    bundle_dir = Path.join(output_root, "#{base_name}-bundle")

    File.write!(markdown_path, render_markdown(snapshot))
    File.write!(json_path, Jason.encode_to_iodata!(json_snapshot(snapshot), pretty: true))
    write_bundle(bundle_dir, snapshot, markdown_path, json_path)

    {:ok,
     %{
       snapshot: snapshot,
       markdown_path: markdown_path,
       json_path: json_path,
       bundle_dir: bundle_dir
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
    #{render_readiness_overview(snapshot.readiness)}
    #{render_readiness(snapshot.readiness.items)}

    ## Cluster Posture
    #{render_cluster(snapshot.cluster)}

    ## Provider Route
    #{render_provider(snapshot.provider)}

    ## Secret Posture
    #{render_secret_posture(snapshot.secrets)}

    ## Operator Auth
    #{render_operator_auth(snapshot.operator)}

    ## Default Agent
    - Status: #{snapshot.default_agent.status}
    - Runtime: #{runtime_label(snapshot.default_agent.runtime.running)}
    - Last started at: #{format_datetime(snapshot.default_agent.runtime.last_started_at)}
    - Bulletin updated at: #{format_datetime(snapshot.default_agent.bulletin.updated_at)}
    - Bulletin memory count: #{snapshot.default_agent.bulletin.memory_count}

    #{render_bulletin(snapshot.default_agent.bulletin.content)}

    ## MCP Integrations
    #{render_mcp_servers(snapshot.mcp)}

    ## Agent MCP Bindings
    #{render_agent_mcp(snapshot.agent_mcp)}

    ## Agent Runtime Snapshots
    #{render_agents(snapshot.agents)}

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

    ## Channel Failure Summary
    #{render_channel_failures(snapshot.channels)}

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

    ## Ingest
    #{render_ingest_runs(snapshot.ingest)}

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

    ## Incidents
    #{render_incidents(snapshot.incidents)}

    ## Audit Trail
    #{render_audit_events(snapshot.audit)}

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

  defp render_readiness_overview(readiness) do
    """
    - Total items: #{readiness.counts.total}
    - OK: #{readiness.counts.ok}
    - Warnings: #{readiness.counts.warn}
    - Required warnings: #{readiness.counts.required_warn}
    - Recommended warnings: #{readiness.counts.recommended_warn}
    - Next steps:
    #{render_readiness_steps(readiness.next_steps)}
    """
    |> String.trim()
  end

  defp render_readiness_steps([]), do: "- none"
  defp render_readiness_steps(steps), do: Enum.map_join(steps, "\n", &"- #{&1}")

  defp render_bulletin(nil), do: "No bulletin generated."
  defp render_bulletin(""), do: "No bulletin generated."

  defp render_bulletin(content) do
    """
    ### Bulletin
    #{content}
    """
  end

  defp render_cluster(cluster) do
    """
    - Mode: #{cluster.mode}
    - Node ID: #{cluster.node_id}
    - Distributed node: #{yes_no(cluster.distributed)}
    - Visible nodes: #{cluster.node_count}
    - Leader: #{cluster.leader_node || "none"}
    - Persistence: #{cluster.persistence}
    - Multi-node ready: #{yes_no(cluster.multi_node_ready)}
    - Detail: #{cluster.detail}
    """
    |> String.trim()
  end

  defp render_provider(provider) do
    capabilities =
      provider.capabilities
      |> Enum.filter(fn {_key, value} -> value end)
      |> Enum.map(fn {key, _value} -> key |> to_string() |> String.replace("_", "-") end)
      |> Enum.join(", ")

    """
    - Name: #{provider.name}
    - Kind: #{provider.kind}
    - Model: #{provider.model || "n/a"}
    - Route source: #{provider.route_source}
    - Warmup: #{provider.warmup_status}
    - Readiness: #{provider.readiness}
    - Fallbacks: #{provider.fallback_count}
    - Capabilities: #{if(capabilities == "", do: "none", else: capabilities)}
    """
    |> String.trim()
  end

  defp render_secret_posture(secrets) do
    scopes =
      secrets.scopes
      |> Enum.map_join("\n", fn scope ->
        "- #{scope.scope}: protected=#{scope.protected_records}/#{scope.total_records} encrypted=#{scope.encrypted_records} env=#{scope.env_backed_records} unresolved=#{scope.unresolved_env_records} plaintext=#{scope.plaintext_records}"
      end)

    issues =
      case secrets.issues do
        [] -> "- none"
        values -> Enum.map_join(values, "\n", &"- #{&1}")
      end

    """
    - Posture: #{secrets.posture}
    - Coverage: #{secrets.protected_records}/#{secrets.total_records} (#{secrets.coverage_percent}%)
    - Encrypted: #{secrets.encrypted_records}
    - Env-backed: #{secrets.env_backed_records}
    - Unresolved env: #{secrets.unresolved_env_records}
    - Plaintext: #{secrets.plaintext_records}
    - Key source: #{secrets.key_source}
    - Scope coverage:
    #{scopes}
    - Current issues:
    #{issues}
    """
    |> String.trim()
  end

  defp render_operator_auth(operator) do
    recent_events =
      case operator.recent_events do
        [] ->
          "- none"

        events ->
          Enum.map_join(events, "\n", fn event ->
            suffix =
              [
                event.expired_by && "expiry=#{event.expired_by}",
                event.reauth? && "reauth=true",
                event.ip && "ip=#{event.ip}"
              ]
              |> Enum.reject(&is_nil_or_empty/1)
              |> Enum.join(" ")

            "- #{format_datetime(event.inserted_at)} [#{String.upcase(event.level)}] #{event.message}#{if(suffix == "", do: "", else: " #{suffix}")}"
          end)
      end

    """
    - Configured: #{yes_no(operator.configured)}
    - Last rotated at: #{format_datetime(operator.last_rotated_at)}
    - Password age: #{operator.password_age_days || "n/a"}
    - Session policy: max #{div(operator.session_max_age_seconds, 3600)}h, idle #{div(operator.idle_timeout_seconds, 60)}m, recent auth #{div(operator.recent_auth_window_seconds, 60)}m
    - Login throttle: #{operator.login_max_attempts} attempts per #{operator.login_window_seconds}s
    - Blocked IPs: #{operator.blocked_login_ips}
    - Recent sign-ins (24h): #{operator.recent_login_success_count}
    - Recent failures (24h): #{operator.recent_login_failure_count}
    - Recent reauth blocks (24h): #{operator.recent_reauth_block_count}
    - Recent session expiries (24h): #{operator.recent_session_expiry_count}
    - Last sign-in: #{format_datetime(operator.last_login_at)}
    - Last failure: #{format_datetime(operator.last_login_failure_at)}
    - Last logout: #{format_datetime(operator.last_logout_at)}
    - Last session expiry: #{format_datetime(operator.last_session_expired_at)}
    - Last expiry reason: #{operator.last_session_expired_reason || "n/a"}
    - Recent auth audit:
    #{recent_events}
    """
    |> String.trim()
  end

  defp render_mcp_servers([]), do: "- none configured"

  defp render_mcp_servers(servers) do
    Enum.map_join(servers, "\n", fn server ->
      "- [#{String.upcase(Atom.to_string(server.status))}] #{server.name} (#{server.transport}): #{server.detail}"
    end)
  end

  defp render_agent_mcp([]), do: "- none"

  defp render_agent_mcp(agent_statuses) do
    Enum.map_join(agent_statuses, "\n", fn status ->
      bindings =
        case status.bindings do
          [] ->
            "none"

          bindings ->
            Enum.map_join(bindings, ", ", fn binding ->
              "#{binding.server_name}[#{if(binding.enabled, do: "on", else: "off")}/#{binding.status}]"
            end)
        end

      "- #{status.agent_name} (#{status.agent_slug}) bindings=#{status.enabled_bindings}/#{status.total_bindings} healthy=#{status.healthy_bindings} :: #{bindings}"
    end)
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

  defp render_agents([]), do: "- none"

  defp render_agents(agents) do
    Enum.map_join(agents, "\n", fn agent ->
      "- #{agent.name} (#{agent.slug}) status=#{agent.status} runtime=#{runtime_label(agent.runtime.running)} readiness=#{agent.runtime.readiness} bulletin_memories=#{agent.bulletin.memory_count} skills=#{agent.skill_count} skill_requires=#{agent.skill_requirement_count} mcp=#{agent.mcp_count} mcp_actions=#{agent.mcp_action_count}"
    end)
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

  defp render_ingest_runs([]), do: "- none"

  defp render_ingest_runs(runs) do
    Enum.map_join(runs, "\n", fn run ->
      "- #{run.source_file} [#{run.status}] created=#{run.created_count} skipped=#{run.skipped_count} archived=#{run.archived_count} at=#{format_datetime(run.inserted_at)}"
    end)
  end

  defp render_conversations([]), do: "- none"

  defp render_conversations(conversations) do
    Enum.map_join(conversations, "\n", fn conversation ->
      delivery = render_conversation_delivery(conversation)
      execution = render_conversation_execution(conversation)
      attachments = render_conversation_attachments(conversation)

      "- ##{conversation.id} #{conversation.channel}/#{conversation.status}: #{conversation.title || conversation.external_ref || "untitled"}#{attachments}#{delivery}#{execution}"
    end)
  end

  defp render_conversation_attachments(conversation) do
    count = conversation_attachment_count(conversation)
    if count > 0, do: " · attachments=#{count}", else: ""
  end

  defp render_conversation_execution(conversation) do
    state = Runtime.conversation_channel_state(conversation.id)

    case state.status do
      nil ->
        ""

      status ->
        steps =
          state.steps
          |> Enum.take(3)
          |> Enum.map(fn step ->
            kind = step["kind"] || "step"
            name = step["name"] || step["label"] || step["id"]
            summary = step["summary"] || step["reason"] || step["label"] || "pending"
            "#{kind}:#{name}:#{step["status"] || "pending"}:#{summary}"
          end)
          |> Enum.join(" | ")

        " · execution=#{status}; steps=#{if(steps == "", do: "none", else: steps)}"
    end
  end

  defp render_conversation_delivery(%{metadata: %{"last_delivery" => delivery}}),
    do: " · delivery=#{render_delivery_summary(delivery)}"

  defp render_conversation_delivery(%{metadata: %{last_delivery: delivery}}),
    do: " · delivery=#{render_delivery_summary(delivery)}"

  defp render_conversation_delivery(_conversation), do: ""

  defp render_delivery_summary(delivery) do
    status = Map.get(delivery, "status") || Map.get(delivery, :status) || "unknown"
    external_ref = Map.get(delivery, "external_ref") || Map.get(delivery, :external_ref)
    retry_count = Map.get(delivery, "retry_count") || Map.get(delivery, :retry_count) || 0
    reason = Map.get(delivery, "reason") || Map.get(delivery, :reason)
    next_retry_at = Map.get(delivery, "next_retry_at") || Map.get(delivery, :next_retry_at)

    dead_lettered_at =
      Map.get(delivery, "dead_lettered_at") || Map.get(delivery, :dead_lettered_at)

    attempt_history =
      Map.get(delivery, "attempt_history") || Map.get(delivery, :attempt_history) || []

    provider_message_id =
      Map.get(delivery, "provider_message_id") || Map.get(delivery, :provider_message_id)

    provider_message_ids =
      Map.get(delivery, "provider_message_ids") || Map.get(delivery, :provider_message_ids) || []

    context =
      delivery
      |> Map.get("reply_context", Map.get(delivery, :reply_context, %{}))
      |> render_reply_context()

    payload = Map.get(delivery, "formatted_payload") || Map.get(delivery, :formatted_payload)

    [
      status,
      external_ref && "ref=#{external_ref}",
      retry_count > 0 && "retry=#{retry_count}",
      reason && "reason=#{reason}",
      provider_message_id && "msg=#{provider_message_id}",
      provider_message_ids != [] && "msg_ids=#{length(provider_message_ids)}",
      next_retry_at && "next_retry=#{format_datetime(next_retry_at)}",
      dead_lettered_at && "dead_lettered_at=#{format_datetime(dead_lettered_at)}",
      attempt_history != [] && "attempts=#{length(attempt_history)}",
      context,
      render_chunk_count(payload),
      render_formatted_payload(payload)
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(", ")
  end

  defp render_reply_context(context) when is_map(context) do
    [
      context["reply_to_message_id"] || context[:reply_to_message_id],
      context["thread_ts"] || context[:thread_ts],
      context["source_message_id"] || context[:source_message_id]
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      values -> "ctx=" <> Enum.join(values, "/")
    end
  end

  defp render_reply_context(_context), do: nil

  defp render_formatted_payload(payload) when is_map(payload) do
    payload
    |> Enum.reject(fn {key, _value} -> to_string(key) in ["text", "content"] end)
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> case do
      [] ->
        content =
          payload["text"] || payload[:text] || payload["content"] || payload[:content]

        if is_binary(content) and content != "" do
          "payload=#{String.slice(content, 0, 48)}"
        end

      entries ->
        "payload=" <> Enum.join(entries, "/")
    end
  end

  defp render_formatted_payload(_payload), do: nil

  defp render_chunk_count(payload) when is_map(payload) do
    case payload["chunk_count"] || payload[:chunk_count] do
      count when is_integer(count) and count > 1 -> "chunks=#{count}"
      _ -> nil
    end
  end

  defp render_chunk_count(_payload), do: nil

  defp conversation_attachment_count(conversation) do
    conversation.id
    |> Runtime.list_turns()
    |> Enum.reduce(0, fn turn, acc ->
      metadata = turn.metadata || %{}
      attachments = metadata["attachments"] || metadata[:attachments] || []
      acc + length(attachments)
    end)
  end

  defp render_backups([]), do: "- none"

  defp render_backups(backups) do
    Enum.map_join(backups, "\n", fn backup ->
      status = if backup["archive_exists"], do: "present", else: "missing"

      verified =
        case backup["verified"] do
          true -> "verified"
          false -> "verify_failed"
          _ -> "unverified"
        end

      "- #{backup["archive_path"]} (archive=#{status}, verify=#{verified}, entries=#{backup["entry_count"]}, size=#{backup["archive_size_bytes"] || 0}, created=#{backup["created_at"]})"
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

  defp render_channel_failures(channels) do
    channels
    |> Map.values()
    |> Enum.map_join("\n", fn status ->
      base =
        "- #{status.channel}: configured=#{yes_no(status.configured)} enabled=#{yes_no(status.enabled)} retryable=#{status.retryable_count || 0} dead_letter=#{status.dead_letter_count || 0} multipart=#{status.multipart_failure_count || 0} attachments=#{status.attachment_failure_count || 0}"

      failures =
        case status.recent_failures do
          [] ->
            " recent_failures=none"

          values ->
            " recent_failures=" <>
              Enum.map_join(values, " | ", fn failure ->
                "#{failure.title}:#{failure.status}:#{failure.reason || "unknown"}"
              end)
        end

      base <> failures
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

  defp render_incidents(%{open: open, acknowledged: acknowledged}) do
    """
    - Open incidents: #{length(open)}
    #{render_incident_items(open)}
    - Acknowledged incidents: #{length(acknowledged)}
    #{render_incident_items(acknowledged)}
    """
    |> String.trim()
  end

  defp render_incident_items([]), do: "  - none"

  defp render_incident_items(events) do
    Enum.map_join(events, "\n", fn event ->
      "  - [#{String.upcase(event.level)}] #{event.category}: #{event.message}"
    end)
  end

  defp render_audit_events([]), do: "- none"

  defp render_audit_events(events) do
    Enum.map_join(events, "\n", fn event ->
      "- [#{event.category}] #{event.message} at #{format_datetime(event.inserted_at)}"
    end)
  end

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

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false

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
      provider: snapshot.provider,
      cluster: snapshot.cluster,
      mcp: snapshot.mcp,
      agent_mcp: snapshot.agent_mcp,
      channels: snapshot.channels,
      telegram: snapshot.telegram,
      operator: snapshot.operator,
      secrets: snapshot.secrets,
      tools: snapshot.tools,
      scheduler: %{
        jobs: Enum.map(snapshot.scheduler.jobs, &json_job/1),
        runs: Enum.map(snapshot.scheduler.runs, &json_job_run/1)
      },
      ingest: Enum.map(snapshot.ingest, &json_ingest_run/1),
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
      incidents: %{
        open: Enum.map(snapshot.incidents.open, &json_safety_event/1),
        acknowledged: Enum.map(snapshot.incidents.acknowledged, &json_safety_event/1)
      },
      audit: Enum.map(snapshot.audit, &json_safety_event/1),
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
      agents: Enum.map(snapshot.agents, &json_agent_snapshot/1),
      skills: Enum.map(snapshot.skills, &json_skill/1),
      conversations: Enum.map(snapshot.conversations, &json_conversation/1)
    }
  end

  defp incident_snapshot(limit) do
    %{
      open: HydraX.Safety.list_events(status: "open", limit: limit),
      acknowledged: HydraX.Safety.list_events(status: "acknowledged", limit: limit)
    }
  end

  defp audit_snapshot(limit) do
    HydraX.Safety.list_events(limit: limit)
    |> Enum.filter(&(&1.category in ["operator", "auth"]))
  end

  defp agent_snapshots do
    Runtime.list_agents()
    |> Enum.map(fn agent ->
      skills = Runtime.list_skills(agent_id: agent.id)
      mcp_actions = agent_mcp_actions(agent.id)

      %{
        id: agent.id,
        name: agent.name,
        slug: agent.slug,
        status: agent.status,
        runtime: Runtime.agent_runtime_status(agent),
        bulletin: Runtime.agent_bulletin(agent.id),
        compaction_policy: Runtime.compaction_policy(agent.id),
        provider_route: Runtime.effective_provider_route(agent.id, "channel"),
        effective_policy: Runtime.effective_policy(agent.id, process_type: "channel"),
        tool_policy: Runtime.effective_tool_policy(agent.id),
        control_policy: Runtime.effective_control_policy(agent.id),
        skill_count: Runtime.enabled_skills(agent.id) |> length(),
        skill_requirement_count:
          skills
          |> Enum.count(fn skill ->
            get_in(skill.metadata || %{}, ["requires"]) not in [nil, []]
          end),
        mcp_count: Runtime.enabled_mcp_servers(agent.id) |> length(),
        mcp_action_count:
          mcp_actions
          |> Enum.reduce(0, fn entry, acc -> acc + length(Map.get(entry, :actions, [])) end),
        mcp_actions: mcp_actions
      }
    end)
  end

  defp write_bundle(bundle_dir, snapshot, markdown_path, json_path) do
    File.mkdir_p!(bundle_dir)

    File.write!(
      Path.join(bundle_dir, "manifest.json"),
      Jason.encode_to_iodata!(
        %{
          generated_at: snapshot.generated_at,
          markdown_path: markdown_path,
          json_path: json_path,
          agent_count: length(snapshot.agents),
          cluster_mode: snapshot.cluster.mode,
          cluster_node_count: snapshot.cluster.node_count,
          mcp_server_count: length(snapshot.mcp),
          agent_mcp_count: length(snapshot.agent_mcp),
          skill_count: length(snapshot.skills),
          open_incident_count: length(snapshot.incidents.open),
          acknowledged_incident_count: length(snapshot.incidents.acknowledged),
          audit_event_count: length(snapshot.audit)
        },
        pretty: true
      )
    )

    File.write!(
      Path.join(bundle_dir, "agents.json"),
      Jason.encode_to_iodata!(Enum.map(snapshot.agents, &json_agent_snapshot/1), pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "cluster.json"),
      Jason.encode_to_iodata!(snapshot.cluster, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "mcp.json"),
      Jason.encode_to_iodata!(snapshot.mcp, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "channels.json"),
      Jason.encode_to_iodata!(snapshot.channels, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "secrets.json"),
      Jason.encode_to_iodata!(snapshot.secrets, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "agent_mcp.json"),
      Jason.encode_to_iodata!(snapshot.agent_mcp, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "skills.json"),
      Jason.encode_to_iodata!(Enum.map(snapshot.skills, &json_skill/1), pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "conversations.json"),
      Jason.encode_to_iodata!(Enum.map(snapshot.conversations, &json_conversation/1),
        pretty: true
      )
    )

    File.write!(
      Path.join(bundle_dir, "incidents.json"),
      Jason.encode_to_iodata!(
        %{
          open: Enum.map(snapshot.incidents.open, &json_safety_event/1),
          acknowledged: Enum.map(snapshot.incidents.acknowledged, &json_safety_event/1)
        },
        pretty: true
      )
    )

    File.write!(
      Path.join(bundle_dir, "audit.json"),
      Jason.encode_to_iodata!(Enum.map(snapshot.audit, &json_safety_event/1), pretty: true)
    )
  end

  defp json_ingest_run(run) do
    %{
      id: run.id,
      agent_id: run.agent_id,
      source_file: run.source_file,
      source_path: run.source_path,
      status: run.status,
      chunk_count: run.chunk_count,
      created_count: run.created_count,
      skipped_count: run.skipped_count,
      archived_count: run.archived_count,
      metadata: run.metadata,
      inserted_at: run.inserted_at
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
    metadata = conversation.metadata || %{}
    delivery = metadata["last_delivery"] || metadata[:last_delivery]
    channel_state = Runtime.conversation_channel_state(conversation.id)
    attachment_count = conversation_attachment_count(conversation)

    %{
      id: conversation.id,
      agent_id: conversation.agent_id,
      channel: conversation.channel,
      status: conversation.status,
      title: conversation.title,
      external_ref: conversation.external_ref,
      metadata: conversation.metadata,
      attachment_count: attachment_count,
      last_delivery: delivery,
      channel_state: %{
        status: channel_state.status,
        provider: channel_state.provider,
        tool_rounds: channel_state.tool_rounds,
        resumable: channel_state.resumable,
        current_step_id: channel_state.current_step_id,
        current_step_index: channel_state.current_step_index,
        steps: channel_state.steps,
        execution_events: Enum.take(channel_state.execution_events, -10),
        tool_results: channel_state.tool_results
      },
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

  defp json_skill(skill) do
    metadata = skill.metadata || %{}

    %{
      id: skill.id,
      agent_id: skill.agent_id,
      slug: skill.slug,
      name: skill.name,
      enabled: skill.enabled,
      description: skill.description,
      source: skill.source,
      path: skill.path,
      version: metadata["version"],
      summary: metadata["summary"],
      tags: metadata["tags"] || [],
      tools: metadata["tools"] || [],
      channels: metadata["channels"] || [],
      requires: metadata["requires"] || [],
      relative_path: metadata["relative_path"] || skill.path
    }
  end

  defp json_agent_snapshot(agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      status: agent.status,
      runtime: agent.runtime,
      bulletin: %{
        content: agent.bulletin.content,
        updated_at: agent.bulletin.updated_at,
        memory_count: agent.bulletin.memory_count
      },
      compaction_policy: agent.compaction_policy,
      provider_route: agent.provider_route,
      tool_policy: agent.tool_policy,
      control_policy: agent.control_policy,
      skill_count: agent.skill_count,
      skill_requirement_count: agent.skill_requirement_count,
      mcp_count: agent.mcp_count,
      mcp_action_count: agent.mcp_action_count,
      mcp_actions: agent.mcp_actions
    }
  end

  defp agent_mcp_actions(agent_id) do
    case Runtime.list_agent_mcp_actions(agent_id) do
      {:ok, %{results: results}} -> results
      _ -> []
    end
  end
end
