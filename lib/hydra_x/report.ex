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
      conversation_limit: Keyword.get(opts, :conversation_limit, 10),
      work_item_limit: Keyword.get(opts, :work_item_limit, 20)
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
      coordination: Runtime.coordination_status(),
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
      conversations: Runtime.list_conversations(limit: filters.conversation_limit),
      work_items: work_item_snapshots(filters.work_item_limit)
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
    Persistence backend: #{snapshot.install.persistence.backend}
    Persistence target: #{snapshot.install.persistence.target || "not configured"}
    Backup mode: #{snapshot.install.persistence.backup_mode}
    Coordination mode: #{snapshot.coordination.mode}
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

    ## Coordination
    #{render_coordination(snapshot.coordination)}

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
    #{render_bulletin_top_memories(snapshot.default_agent.bulletin.top_memories || [])}

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
    - Active streaming deliveries: #{snapshot.telegram.streaming_count || 0}
    - Last error: #{snapshot.telegram.last_error || "none"}
    - Recent failed conversations:
    #{render_telegram_failures(snapshot.telegram.recent_failures)}
    - Active streaming conversations:
    #{render_telegram_failures(snapshot.telegram.recent_streaming || [])}

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
    - Coordination: #{render_scheduler_coordination(snapshot.scheduler.coordination)}
    - Skip reasons: #{render_skip_reason_counts(snapshot.scheduler.skipped_reason_counts)}
    - Ingress replay: #{render_scheduler_pass(snapshot.scheduler.pending_ingress, "processed_count", "processed")}
    - Ownership replay: #{render_scheduler_pass(snapshot.scheduler.ownership_handoffs, "resumed_count", "resumed")}
    - Deferred delivery replay: #{render_scheduler_pass(snapshot.scheduler.deferred_deliveries, "delivered_count", "delivered")}

    ### Jobs
    #{render_jobs(snapshot.scheduler.jobs)}

    ### Recent Runs
    #{render_job_runs(snapshot.scheduler.runs)}

    ### Lease-Owned Skips
    #{render_lease_owned_skips(snapshot.scheduler.lease_owned_skips)}

    ## Ingest
    #{render_ingest_runs(snapshot.ingest)}

    ## Conversations
    #{render_conversations(snapshot.conversations)}

    ## Autonomous Work Items
    #{render_work_items(snapshot.work_items)}

    ## Observability
    #{render_observability_summary(snapshot.observability.telemetry_summary)}

    ### Recent Telemetry Events
    #{render_recent_telemetry_events(snapshot.observability.telemetry.recent_events)}

    - Persistence: #{render_persistence_summary(snapshot.observability.system.persistence)}
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
      runs: Enum.take(status.runs, limit),
      skipped_reason_counts: status.skipped_reason_counts,
      lease_owned_skips: status.lease_owned_skips,
      coordination: status.coordination,
      pending_ingress: status.pending_ingress,
      ownership_handoffs: status.ownership_handoffs,
      deferred_deliveries: status.deferred_deliveries
    }
  end

  defp render_scheduler_coordination(%{} = coordination) when map_size(coordination) > 0 do
    [
      coordination[:mode] || coordination["mode"],
      coordination[:owner] || coordination["owner"]
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" / ")
  end

  defp render_scheduler_coordination(_coordination), do: "unknown"

  defp render_scheduler_pass(pass, primary_key, verb) do
    count = render_scheduler_count(pass, primary_key)
    skipped = render_scheduler_count(pass, "skipped_count")
    errors = render_scheduler_count(pass, "error_count")
    owner = render_scheduler_owner(pass) || "unknown"
    "#{verb}=#{count}; skipped=#{skipped}; errors=#{errors}; owner=#{owner}"
  end

  defp render_scheduler_count(pass, key) when is_map(pass) do
    Map.get(pass, key) || Map.get(pass, scheduler_count_key(key)) || 0
  end

  defp render_scheduler_count(_pass, _key), do: 0

  defp render_scheduler_owner(pass) when is_map(pass), do: pass["owner"] || pass[:owner]
  defp render_scheduler_owner(_pass), do: nil

  defp scheduler_count_key("processed_count"), do: :processed_count
  defp scheduler_count_key("resumed_count"), do: :resumed_count
  defp scheduler_count_key("delivered_count"), do: :delivered_count
  defp scheduler_count_key("skipped_count"), do: :skipped_count
  defp scheduler_count_key("error_count"), do: :error_count
  defp scheduler_count_key(other), do: other

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

  defp render_bulletin_top_memories([]), do: nil

  defp render_bulletin_top_memories(memories) do
    """
    ### Top Bulletin Memories
    #{render_bulletin_memory_lines(memories)}
    """
  end

  defp render_bulletin_memory_lines(memories) do
    Enum.map_join(memories, "\n", fn memory ->
      [
        memory[:type],
        "score=#{memory[:score]}",
        memory[:source_file] && "file=#{memory[:source_file]}",
        memory[:source_section] && "section=#{memory[:source_section]}",
        memory[:source_channel] && "channel=#{memory[:source_channel]}",
        (memory[:reasons] || []) != [] && "reasons=#{Enum.join(memory[:reasons], ", ")}",
        render_score_breakdown(memory[:score_breakdown] || %{}),
        truncate_text(memory[:content], 120)
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" | ")
      |> then(&("- " <> &1))
    end)
  end

  defp render_cluster(cluster) do
    """
    - Mode: #{cluster.mode}
    - Node ID: #{cluster.node_id}
    - Distributed node: #{yes_no(cluster.distributed)}
    - Visible nodes: #{cluster.node_count}
    - Leader: #{cluster.leader_node || "none"}
    - Persistence: #{cluster.persistence}
    - Persistence backend: #{cluster.persistence_backend}
    - Persistence target: #{cluster.persistence_target || "not configured"}
    - Multi-node ready: #{yes_no(cluster.multi_node_ready)}
    - Detail: #{cluster.detail}
    """
    |> String.trim()
  end

  defp render_coordination(coordination) do
    leases =
      case coordination.active_leases do
        [] ->
          "- none"

        values ->
          Enum.map_join(values, "\n", fn lease ->
            "- #{lease.name}: #{lease.owner} expires=#{format_datetime(lease.expires_at)}"
          end)
      end

    """
    - Mode: #{coordination.mode}
    - Backend: #{coordination.backend}
    - Enabled: #{yes_no(coordination.enabled)}
    - Local owner: #{coordination.owner}
    - Active leases: #{coordination.lease_count}
    - Scheduler owner: #{coordination.scheduler_owner || "none"}
    - Scheduler expires at: #{format_datetime(coordination.scheduler_expires_at)}
    - Lease catalog:
    #{leases}
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

  defp render_memory_triage(%{
         counts: counts,
         embedding: embedding,
         recent_conflicts: recent_conflicts,
         ranked_memories: ranked_memories
       }) do
    """
    - Active: #{Map.get(counts, "active", 0)}
    - Conflicted: #{Map.get(counts, "conflicted", 0)}
    - Superseded: #{Map.get(counts, "superseded", 0)}
    - Merged: #{Map.get(counts, "merged", 0)}
    - Embeddings: active=#{embedding.active_backend || "none"} model=#{embedding.active_model || "none"} embedded=#{embedding.embedded_count} missing=#{embedding.unembedded_count} stale=#{embedding.stale_count} fallback=#{embedding.fallback_count} degraded=#{yes_no(embedding.degraded?)}
    - Top ranked active memories:
    #{render_ranked_memories(ranked_memories)}
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
      metadata = run.metadata || %{}
      reason = metadata["status_reason"] || metadata[:status_reason]
      lease_owner = metadata["lease_owner"] || metadata[:lease_owner]

      [
        "##{run.id}",
        "job=#{run.scheduled_job_id}",
        "status=#{run.status}",
        "started=#{format_datetime(run.started_at)}",
        "delivery=#{render_delivery_status(run)}",
        reason && "reason=#{reason}",
        lease_owner && "lease_owner=#{lease_owner}"
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" ")
      |> then(&("- " <> &1))
    end)
  end

  defp render_skip_reason_counts([]), do: "none"

  defp render_skip_reason_counts(reason_counts) do
    Enum.map_join(reason_counts, ", ", fn %{reason: reason, count: count} ->
      "#{humanize_skip_reason(reason)}=#{count}"
    end)
  end

  defp render_lease_owned_skips([]), do: "- none"

  defp render_lease_owned_skips(runs) do
    Enum.map_join(runs, "\n", fn run ->
      metadata = run.metadata || %{}
      lease_owner = metadata["lease_owner"] || metadata[:lease_owner] || "unknown"
      lease_expires_at = metadata["lease_expires_at"] || metadata[:lease_expires_at]

      [
        "##{run.id}",
        run.scheduled_job && run.scheduled_job.name,
        "owner=#{lease_owner}",
        lease_expires_at && "expires=#{format_datetime(lease_expires_at)}"
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" ")
      |> then(&("- " <> &1))
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

  defp render_work_items([]), do: "- none"

  defp render_work_items(work_items) do
    Enum.map_join(work_items, "\n", fn item ->
      artifacts =
        item.artifacts
        |> Enum.map(fn artifact ->
          latest_approval =
            artifact.approvals
            |> List.first()
            |> case do
              nil -> artifact.review_status
              record -> "#{artifact.review_status}/#{record.decision}"
            end

          "#{artifact.type}:#{latest_approval}"
        end)
        |> Enum.join(",")

      promoted_memories =
        item.promoted_memories
        |> Enum.map(fn memory ->
          "#{memory.type}:#{truncate_text(memory.content, 48)}"
        end)
        |> Enum.join(",")

      latest_approval =
        item.approvals
        |> List.first()
        |> case do
          nil -> "pending"
          record -> "#{record.decision}/#{record.requested_action}"
        end

      publish = render_work_item_publish_summary(item)

      [
        "##{item.id}",
        "#{item.kind}/#{item.status}",
        "role=#{item.assigned_role}",
        "stage=#{item.approval_stage}",
        "approval=#{latest_approval}",
        item.result_refs["extension_enablement_status"] &&
          "enablement=#{item.result_refs["extension_enablement_status"]}",
        artifacts != "" && "artifacts=#{artifacts}",
        promoted_memories != "" && "promoted=#{promoted_memories}",
        publish && "publish=#{publish}",
        item.goal
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" ")
      |> then(&("- " <> &1))
    end)
  end

  defp render_conversation_attachments(conversation) do
    count = conversation_attachment_count(conversation)
    if count > 0, do: " · attachments=#{count}", else: ""
  end

  defp render_conversation_execution(conversation) do
    state = Runtime.conversation_channel_state(conversation.id)
    compaction = Runtime.conversation_compaction(conversation.id)

    case state.status do
      nil ->
        render_conversation_compaction(compaction)

      status ->
        steps =
          state.steps
          |> Enum.take(3)
          |> Enum.map(&render_conversation_step_summary/1)
          |> Enum.join(" | ")

        owner = render_conversation_owner(state.ownership)
        handoff = render_conversation_handoff(state.handoff)
        pending_response = render_conversation_pending_response(state.pending_response)
        stream_capture = render_conversation_stream_capture(state.stream_capture)

        [
          "execution=#{status}",
          state.resume_stage && "resume_from=#{state.resume_stage}",
          state.stale_stream && "stale_stream=yes",
          "owner=#{owner}",
          handoff && "handoff=#{handoff}",
          pending_response && "pending_response=#{pending_response}",
          stream_capture && "stream_capture=#{stream_capture}",
          "steps=#{if(steps == "", do: "none", else: steps)}",
          render_conversation_compaction_detail(compaction)
        ]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join("; ")
        |> then(&(" · " <> &1))
    end
  end

  defp render_conversation_compaction(%{summary: nil, supporting_memories: []}), do: ""

  defp render_conversation_compaction(compaction) do
    detail = render_conversation_compaction_detail(compaction)
    if detail == nil, do: "", else: " · #{detail}"
  end

  defp render_conversation_compaction_detail(compaction) do
    memories = compaction.supporting_memories || []

    [
      compaction.level && "compaction=#{compaction.level}",
      compaction.summary_source && "compaction_source=#{compaction.summary_source}",
      memories != [] && "compaction_memories=#{length(memories)}",
      memories != [] && "compaction_top=#{render_compaction_memory_summary(hd(memories))}"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  defp render_compaction_memory_summary(memory) do
    [
      memory.type,
      "score=#{memory.score}",
      render_ranked_source(%{
        "source_file" => memory.source_file,
        "source_section" => memory.source_section,
        "source_channel" => memory.source_channel
      }),
      render_score_breakdown(memory.score_breakdown || %{}),
      truncate_text(memory.content, 80)
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" | ")
  end

  defp render_conversation_owner(%{} = ownership) when map_size(ownership) > 0 do
    [ownership["mode"], ownership["owner"], ownership["stage"]]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join("/")
  end

  defp render_conversation_owner(_ownership), do: "n/a"

  defp render_conversation_handoff(%{} = handoff) when map_size(handoff) > 0 do
    [handoff["status"], handoff["waiting_for"], handoff["owner"]]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join("/")
  end

  defp render_conversation_handoff(_handoff), do: nil

  defp render_conversation_pending_response(%{} = response) when map_size(response) > 0 do
    provider = get_in(response, ["metadata", "provider"]) || "provider"
    content = response["content"] || ""
    "#{provider}:#{String.slice(content, 0, 60)}"
  end

  defp render_conversation_pending_response(_response), do: nil

  defp render_conversation_stream_capture(%{} = capture) when map_size(capture) > 0 do
    provider = capture["provider"] || "provider"
    chunk_count = capture["chunk_count"] || 0
    "#{provider}:chunks=#{chunk_count}"
  end

  defp render_conversation_stream_capture(_capture), do: nil

  defp render_conversation_step_summary(step) do
    kind = step["kind"] || "step"
    name = step["name"] || step["label"] || step["id"]
    summary = step["summary"] || step["reason"] || step["label"] || "pending"

    extras =
      [
        step["lifecycle"] && "lifecycle=#{step["lifecycle"]}",
        step["result_source"] && "source=#{step["result_source"]}",
        step["replay_count"] && step["replay_count"] > 0 && "replay=#{step["replay_count"]}",
        render_conversation_step_retry(step["retry_state"]),
        render_conversation_step_attempts(step["attempt_history"])
      ]
      |> Enum.reject(&is_nil_or_empty/1)

    details =
      case extras do
        [] -> ""
        _ -> " [" <> Enum.join(extras, ", ") <> "]"
      end

    "#{kind}:#{name}:#{step["status"] || "pending"}:#{summary}#{details}"
  end

  defp render_conversation_step_retry(%{} = retry_state) when map_size(retry_state) > 0 do
    [
      retry_state["last_status"],
      retry_state["attempt_count"] && "attempts=#{retry_state["attempt_count"]}",
      retry_state["retry_count"] && "retries=#{retry_state["retry_count"]}",
      retry_state["result_source"] && "source=#{retry_state["result_source"]}",
      retry_state["last_error"] && "error=#{retry_state["last_error"]}"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      values -> "retry=" <> Enum.join(values, "/")
    end
  end

  defp render_conversation_step_retry(_retry_state), do: nil

  defp render_conversation_step_attempts(history) when is_list(history) and history != [] do
    "attempt_history=" <>
      Enum.map_join(history, "->", fn attempt ->
        status = attempt["status"] || attempt[:status] || "unknown"

        case attempt["at"] || attempt[:at] do
          nil -> status
          at -> "#{status}@#{format_datetime(at)}"
        end
      end)
  end

  defp render_conversation_step_attempts(_history), do: nil

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

    stream_message_id =
      get_in(delivery, ["reply_context", "stream_message_id"]) ||
        get_in(delivery, [:reply_context, :stream_message_id])

    context =
      delivery
      |> Map.get("reply_context", Map.get(delivery, :reply_context, %{}))
      |> render_reply_context()

    metadata = Map.get(delivery, "metadata") || Map.get(delivery, :metadata) || %{}
    payload = Map.get(delivery, "formatted_payload") || Map.get(delivery, :formatted_payload)

    [
      status,
      external_ref && "ref=#{external_ref}",
      retry_count > 0 && "retry=#{retry_count}",
      reason && "reason=#{reason}",
      provider_message_id && "msg=#{provider_message_id}",
      stream_message_id && "stream_msg=#{stream_message_id}",
      provider_message_ids != [] && "msg_ids=#{length(provider_message_ids)}",
      next_retry_at && "next_retry=#{format_datetime(next_retry_at)}",
      dead_lettered_at && "dead_lettered_at=#{format_datetime(dead_lettered_at)}",
      attempt_history != [] && "attempts=#{length(attempt_history)}",
      render_delivery_transport(metadata),
      context,
      render_chunk_count(payload),
      render_formatted_payload(payload),
      render_delivery_preview(payload)
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

  defp render_delivery_transport(metadata) when is_map(metadata) do
    transport = metadata["transport"] || metadata[:transport]
    topic = metadata["transport_topic"] || metadata[:transport_topic]

    cond do
      is_nil_or_empty(transport) ->
        nil

      is_nil_or_empty(topic) ->
        ["transport=#{transport}", transport_semantics_label(transport)]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join(", ")

      true ->
        ["transport=#{transport}@#{topic}", transport_semantics_label(transport)]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join(", ")
    end
  end

  defp render_delivery_transport(_metadata), do: nil

  defp render_delivery_preview(payload) when is_map(payload) do
    case payload["text"] || payload[:text] || payload["content"] || payload[:content] do
      value when is_binary(value) and value != "" -> "preview=#{String.slice(value, 0, 48)}"
      _ -> nil
    end
  end

  defp render_delivery_preview(_payload), do: nil

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

      "- #{backup["archive_path"]} (archive=#{status}, verify=#{verified}, entries=#{backup["entry_count"]}, size=#{backup["archive_size_bytes"] || 0}, created=#{backup["created_at"]}, backup_mode=#{backup["persistence"]["backup_mode"] || "bundled_database"})"
    end)
  end

  defp render_persistence_summary(persistence) do
    "#{persistence.backend} target=#{persistence.target || "not configured"} backup_mode=#{persistence.backup_mode}"
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
        "- #{status.channel}: configured=#{yes_no(status.configured)} enabled=#{yes_no(status.enabled)} retryable=#{status.retryable_count || 0} dead_letter=#{status.dead_letter_count || 0} multipart=#{status.multipart_failure_count || 0} attachments=#{status.attachment_failure_count || 0} streaming=#{status.streaming_count || 0}"

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

      streaming =
        case Map.get(status, :recent_streaming, []) do
          [] ->
            " recent_streaming=none"

          values ->
            " recent_streaming=" <>
              Enum.map_join(values, " | ", fn stream ->
                payload = stream.formatted_payload || %{}

                preview =
                  payload["text"] || payload[:text] || payload["content"] || payload[:content]

                [
                  stream.title,
                  stream.status,
                  if(stream.chunk_count, do: "chunks=#{stream.chunk_count}"),
                  if(stream.provider_message_id, do: "msg=#{stream.provider_message_id}"),
                  if(stream.stream_message_id, do: "stream_msg=#{stream.stream_message_id}"),
                  if(stream.transport, do: "transport=#{stream.transport}"),
                  if(stream.transport, do: transport_semantics_label(stream.transport)),
                  if(preview, do: "preview=#{String.slice(preview, 0, 40)}")
                ]
                |> Enum.reject(&is_nil_or_empty/1)
                |> Enum.join(":")
              end)
        end

      base <> failures <> streaming
    end)
  end

  defp transport_semantics_label("telegram_message_edit"), do: "edits Telegram message"
  defp transport_semantics_label("slack_chat_update"), do: "updates Slack thread"
  defp transport_semantics_label("discord_message_patch"), do: "patches Discord message"
  defp transport_semantics_label("session_pubsub"), do: "publishes Webchat session previews"
  defp transport_semantics_label("transport error"), do: "stream transport error"
  defp transport_semantics_label(_value), do: nil

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

  defp render_ranked_memories([]), do: "- none"

  defp render_ranked_memories(ranked_memories) do
    Enum.map_join(ranked_memories, "\n", fn ranked ->
      memory = ranked.entry
      metadata = memory.metadata || %{}

      [
        memory.type,
        "score=#{ranked.score}",
        "importance=#{memory.importance}",
        "reasons=#{Enum.join(ranked.reasons || [], ", ")}",
        render_ranked_source(metadata),
        render_score_breakdown(ranked.score_breakdown || %{}),
        truncate_text(memory.content, 120)
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" | ")
      |> then(&("- " <> &1))
    end)
  end

  defp render_ranked_source(metadata) do
    [
      metadata["source_file"] && "file=#{metadata["source_file"]}",
      metadata["source_section"] && "section=#{metadata["source_section"]}",
      metadata["source_channel"] && "channel=#{metadata["source_channel"]}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp render_score_breakdown(score_breakdown) when map_size(score_breakdown) == 0, do: nil

  defp render_score_breakdown(score_breakdown) do
    breakdown =
      score_breakdown
      |> Enum.sort_by(fn {_key, value} -> -value end)
      |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)

    "breakdown=#{breakdown}"
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

  defp truncate_text(value, limit) when is_binary(value) and byte_size(value) > limit do
    String.slice(value, 0, limit - 3) <> "..."
  end

  defp truncate_text(value, _limit), do: value

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

  defp humanize_skip_reason("lease_owned_elsewhere"), do: "lease owned elsewhere"
  defp humanize_skip_reason("circuit_open"), do: "circuit open"
  defp humanize_skip_reason("outside_active_hours"), do: "outside active hours"
  defp humanize_skip_reason(reason) when is_binary(reason), do: String.replace(reason, "_", " ")
  defp humanize_skip_reason(_reason), do: "unknown"

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
      coordination: snapshot.coordination,
      mcp: snapshot.mcp,
      agent_mcp: snapshot.agent_mcp,
      channels: snapshot.channels,
      telegram: snapshot.telegram,
      operator: snapshot.operator,
      secrets: snapshot.secrets,
      tools: snapshot.tools,
      scheduler: %{
        jobs: Enum.map(snapshot.scheduler.jobs, &json_job/1),
        runs: Enum.map(snapshot.scheduler.runs, &json_job_run/1),
        skipped_reason_counts: snapshot.scheduler.skipped_reason_counts,
        lease_owned_skips: Enum.map(snapshot.scheduler.lease_owned_skips, &json_job_run/1),
        coordination: snapshot.scheduler.coordination,
        pending_ingress: snapshot.scheduler.pending_ingress,
        ownership_handoffs: snapshot.scheduler.ownership_handoffs,
        deferred_deliveries: snapshot.scheduler.deferred_deliveries
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
        embedding: snapshot.memory.embedding,
        ranked_memories: Enum.map(snapshot.memory.ranked_memories, &json_ranked_memory/1),
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
          memory_count: snapshot.default_agent.bulletin.memory_count,
          top_memories: snapshot.default_agent.bulletin.top_memories || []
        }
      },
      agents: Enum.map(snapshot.agents, &json_agent_snapshot/1),
      skills: Enum.map(snapshot.skills, &json_skill/1),
      conversations: Enum.map(snapshot.conversations, &json_conversation/1),
      work_items: Enum.map(snapshot.work_items, &json_work_item/1)
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
          coordination_mode: snapshot.coordination.mode,
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
      Path.join(bundle_dir, "coordination.json"),
      Jason.encode_to_iodata!(snapshot.coordination, pretty: true)
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
      Path.join(bundle_dir, "memory.json"),
      Jason.encode_to_iodata!(json_memory_snapshot(snapshot.memory), pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "conversations.json"),
      Jason.encode_to_iodata!(Enum.map(snapshot.conversations, &json_conversation/1),
        pretty: true
      )
    )

    File.write!(
      Path.join(bundle_dir, "work_items.json"),
      Jason.encode_to_iodata!(Enum.map(snapshot.work_items, &json_work_item/1), pretty: true)
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
    compaction = Runtime.conversation_compaction(conversation.id)
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
        ownership: channel_state.ownership,
        provider: channel_state.provider,
        tool_rounds: channel_state.tool_rounds,
        resumable: channel_state.resumable,
        current_step_id: channel_state.current_step_id,
        current_step_index: channel_state.current_step_index,
        resume_stage: channel_state.resume_stage,
        stale_stream: channel_state.stale_stream,
        handoff: channel_state.handoff,
        pending_response: channel_state.pending_response,
        stream_capture: channel_state.stream_capture,
        steps: channel_state.steps,
        execution_events: Enum.take(channel_state.execution_events, -10),
        tool_results: channel_state.tool_results
      },
      compaction: %{
        level: compaction.level,
        summary: compaction.summary,
        summary_source: compaction.summary_source,
        supporting_memories: compaction.supporting_memories,
        updated_at: compaction.updated_at
      },
      last_message_at: conversation.last_message_at,
      inserted_at: conversation.inserted_at,
      updated_at: conversation.updated_at
    }
  end

  defp json_work_item(item) do
    %{
      id: item.id,
      kind: item.kind,
      goal: item.goal,
      status: item.status,
      execution_mode: item.execution_mode,
      assigned_role: item.assigned_role,
      assigned_agent_id: item.assigned_agent_id,
      approval_stage: item.approval_stage,
      review_required: item.review_required,
      priority: item.priority,
      result_refs: item.result_refs,
      metadata: item.metadata,
      publish_follow_up: work_item_publish_snapshot(item),
      inserted_at: item.inserted_at,
      updated_at: item.updated_at,
      promoted_memories:
        Enum.map(item.promoted_memories || [], fn memory ->
          json_promoted_memory(memory)
        end),
      artifacts:
        Enum.map(item.artifacts, fn artifact ->
          json_artifact_snapshot(artifact)
        end),
      approvals:
        Enum.map(item.approvals, fn record ->
          %{
            id: record.id,
            decision: record.decision,
            requested_action: record.requested_action,
            rationale: record.rationale,
            reviewer_agent_id: record.reviewer_agent_id,
            inserted_at: record.inserted_at
          }
        end)
    }
  end

  defp work_item_snapshots(limit) do
    Runtime.list_work_items(limit: limit)
    |> Enum.map(fn item ->
      approvals =
        Runtime.approval_records_for_subject("work_item", item.id)
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      %{
        id: item.id,
        kind: item.kind,
        goal: item.goal,
        status: item.status,
        execution_mode: item.execution_mode,
        assigned_role: item.assigned_role,
        assigned_agent_id: item.assigned_agent_id,
        approval_stage: item.approval_stage,
        review_required: item.review_required,
        priority: item.priority,
        result_refs: item.result_refs || %{},
        metadata: item.metadata || %{},
        inserted_at: item.inserted_at,
        updated_at: item.updated_at,
        promoted_memories: Runtime.promoted_work_item_memories(item),
        artifacts:
          Runtime.work_item_artifacts(item.id)
          |> Enum.map(fn artifact ->
            artifact
            |> Map.from_struct()
            |> Map.put(:approvals, Runtime.artifact_approval_records(artifact.id))
          end),
        approvals: approvals
      }
    end)
  end

  defp render_work_item_publish_summary(item) do
    case work_item_publish_snapshot(item) do
      nil ->
        nil

      %{type: "publish_summary", status: status, channel: channel, target: target} ->
        [
          status,
          channel || "report",
          target && "-> #{target}"
        ]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join(" ")

      %{type: "queued_follow_up", count: count} ->
        "queued #{count}"
    end
  end

  defp work_item_publish_snapshot(item) do
    cond do
      get_in(item.metadata || %{}, ["task_type"]) == "publish_summary" ->
        delivery = get_in(item.metadata || %{}, ["delivery"]) || %{}

        %{
          type: "publish_summary",
          status:
            if(
              Enum.any?(item.artifacts || [], &(&1.type == "delivery_brief")),
              do: "delivery_brief_ready",
              else: item.status
            ),
          channel: delivery["channel"] || delivery["mode"] || "report",
          target: delivery["target"]
        }

      List.wrap(get_in(item.result_refs || %{}, ["follow_up_work_item_ids"])) != [] ->
        %{
          type: "queued_follow_up",
          count: length(List.wrap(get_in(item.result_refs || %{}, ["follow_up_work_item_ids"])))
        }

      true ->
        nil
    end
  end

  defp json_artifact_snapshot(artifact) do
    %{
      id: artifact.id,
      type: artifact.type,
      title: artifact.title,
      summary: artifact.summary,
      review_status: artifact.review_status,
      payload: artifact.payload,
      approvals:
        Enum.map(Map.get(artifact, :approvals, []), fn record ->
          %{
            id: record.id,
            decision: record.decision,
            requested_action: record.requested_action,
            rationale: record.rationale,
            reviewer_agent_id: record.reviewer_agent_id,
            inserted_at: record.inserted_at
          }
        end)
    }
  end

  defp json_promoted_memory(memory) do
    %{
      id: memory.id,
      type: memory.type,
      status: memory.status,
      content: memory.content,
      importance: memory.importance,
      metadata: memory.metadata,
      inserted_at: memory.inserted_at,
      updated_at: memory.updated_at
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

  defp json_ranked_memory(ranked) do
    memory = ranked.entry
    metadata = memory.metadata || %{}

    %{
      memory: json_memory(memory),
      score: ranked.score,
      vector_score: ranked[:vector_score],
      lexical_rank: ranked[:lexical_rank],
      semantic_rank: ranked[:semantic_rank],
      reasons: ranked[:reasons] || [],
      score_breakdown: ranked[:score_breakdown] || %{},
      provenance: %{
        source_file: metadata["source_file"],
        source_section: metadata["source_section"],
        source_channel: metadata["source_channel"],
        embedding_backend: metadata["embedding_backend"],
        embedding_model: metadata["embedding_model"],
        embedding_fallback_from: metadata["embedding_fallback_from"]
      }
    }
  end

  defp json_memory_snapshot(memory_snapshot) do
    %{
      agent_id: memory_snapshot.agent_id,
      agent_name: memory_snapshot.agent_name,
      counts: memory_snapshot.counts,
      embedding: memory_snapshot.embedding,
      ranked_memories: Enum.map(memory_snapshot.ranked_memories, &json_ranked_memory/1),
      recent_conflicts: Enum.map(memory_snapshot.recent_conflicts, &json_memory/1)
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
        memory_count: agent.bulletin.memory_count,
        top_memories: agent.bulletin.top_memories || []
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
