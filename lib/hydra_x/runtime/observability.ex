defmodule HydraX.Runtime.Observability do
  @moduledoc """
  Health snapshots, readiness reports, system status, and observability aggregation.
  """

  import Ecto.Query

  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.Memory
  alias HydraX.Security.Secrets
  alias HydraX.Security.LoginThrottle
  alias HydraX.Safety

  alias HydraX.Repo

  alias HydraX.Runtime.{
    AgentProfile,
    DiscordConfig,
    Helpers,
    OperatorSecret,
    ProviderConfig,
    SlackConfig,
    TelegramConfig
  }

  def health_snapshot(opts \\ []) do
    provider = HydraX.Runtime.Providers.enabled_provider()
    default_agent = HydraX.Runtime.Agents.get_default_agent()

    default_agent_runtime =
      default_agent && HydraX.Runtime.Agents.agent_runtime_status(default_agent)

    default_agent_route =
      default_agent &&
        HydraX.Runtime.Providers.effective_provider_route(default_agent.id, "channel")

    budget_policy = default_agent && HydraX.Budget.ensure_policy!(default_agent.id)
    memory_status = memory_triage_status(default_agent)
    safety_counts = HydraX.Safety.recent_counts()
    system = system_status()
    backups = backup_status()
    secrets = secret_storage_status()
    control_policy = control_policy_status()
    effective_policy = effective_policy_status(default_agent && default_agent.id)
    safety_errors = Map.get(safety_counts, "error", 0)
    safety_warnings = Map.get(safety_counts, "warn", 0)

    agents = HydraX.Runtime.Agents.list_agents()
    telegram_config = HydraX.Runtime.TelegramAdmin.enabled_telegram_config()
    discord_config = HydraX.Runtime.DiscordAdmin.enabled_discord_config()
    slack_config = HydraX.Runtime.SlackAdmin.enabled_slack_config()
    webchat_config = HydraX.Runtime.WebchatAdmin.enabled_webchat_config()
    mcp_servers = HydraX.Runtime.MCPServers.list_mcp_servers()
    mcp_statuses = HydraX.Runtime.MCPServers.mcp_statuses()
    operator = operator_status()
    cluster = cluster_status()
    coordination = coordination_status()
    autonomy = autonomy_status()

    checks = [
      %{name: "database", status: :ok, detail: database_health_detail(system.persistence)},
      %{
        name: "agents",
        status: if(agents == [], do: :warn, else: :ok),
        detail: "#{length(agents)} configured"
      },
      %{
        name: "providers",
        status:
          cond do
            default_agent_runtime && default_agent_runtime.readiness == "degraded" -> :warn
            provider -> :ok
            true -> :warn
          end,
        detail:
          provider_health_detail(
            provider,
            default_agent,
            default_agent_runtime,
            default_agent_route
          )
      },
      %{
        name: "auth",
        status:
          cond do
            not operator.configured -> :warn
            operator.password_stale? -> :warn
            operator.recent_login_failure_count > 0 -> :warn
            operator.recent_session_expiry_count > 0 -> :warn
            true -> :ok
          end,
        detail: operator_detail(operator)
      },
      %{
        name: "secrets",
        status:
          cond do
            secrets.unresolved_env_records > 0 -> :warn
            secrets.plaintext_records > 0 -> :warn
            secrets.total_records > 0 -> :ok
            true -> :warn
          end,
        detail: secret_detail(secrets)
      },
      %{
        name: "channels",
        status:
          if(telegram_config || discord_config || slack_config || webchat_config,
            do: :ok,
            else: :warn
          ),
        detail: channel_health_detail(channel_statuses())
      },
      %{
        name: "mcp",
        status:
          cond do
            mcp_servers == [] -> :warn
            Enum.all?(mcp_statuses, &(&1.status == :ok)) -> :ok
            true -> :warn
          end,
        detail: mcp_health_detail(mcp_statuses)
      },
      %{
        name: "cluster",
        status: if(cluster.enabled, do: :warn, else: :ok),
        detail: cluster_detail(cluster)
      },
      %{
        name: "coordination",
        status: if(coordination.enabled, do: :warn, else: :ok),
        detail: coordination_detail(coordination)
      },
      %{
        name: "budget",
        status: if(budget_policy, do: :ok, else: :warn),
        detail:
          case budget_policy do
            nil -> "no policy configured"
            policy -> "daily #{policy.daily_limit}; conversation #{policy.conversation_limit}"
          end
      },
      %{
        name: "memory",
        status: if(Map.get(memory_status.counts, "conflicted", 0) > 0, do: :warn, else: :ok),
        detail:
          "active #{Map.get(memory_status.counts, "active", 0)}; conflicted #{Map.get(memory_status.counts, "conflicted", 0)}; embedded #{memory_status.embedding.embedded_count}/#{memory_status.embedding.total_count}; missing #{memory_status.embedding.unembedded_count}; stale #{memory_status.embedding.stale_count}; backend #{memory_status.embedding.active_backend}"
      },
      %{
        name: "safety",
        status: if(safety_errors > 0 or safety_warnings > 0, do: :warn, else: :ok),
        detail:
          cond do
            safety_errors > 0 ->
              "#{safety_errors} errors; #{safety_warnings} warnings in the last 24h"

            safety_warnings > 0 ->
              "#{safety_warnings} warnings in the last 24h"

            true ->
              "no recent safety events"
          end
      },
      %{
        name: "autonomy",
        status:
          if(
            autonomy.autonomy_agent_count > 0 and Map.get(autonomy.counts, "failed", 0) == 0,
            do: :ok,
            else: :warn
          ),
        detail: autonomy_detail(autonomy)
      },
      %{
        name: "tools",
        status: :ok,
        detail: tool_detail(tool_status())
      },
      %{
        name: "control_policy",
        status: :ok,
        detail: control_policy_detail(control_policy)
      },
      %{
        name: "effective_policy",
        status: :ok,
        detail: effective_policy_detail(effective_policy)
      },
      (
        scheduled_jobs = HydraX.Runtime.Jobs.list_scheduled_jobs(limit: 5)

        %{
          name: "scheduler",
          status: if(scheduled_jobs == [], do: :warn, else: :ok),
          detail:
            case scheduled_jobs do
              [] -> "no scheduled jobs configured"
              jobs -> "#{length(jobs)} jobs configured"
            end
        }
      ),
      %{
        name: "system",
        status: if(system.alarms == [], do: :ok, else: :warn),
        detail:
          case system.alarms do
            [] -> "no active OTP alarms"
            alarms -> Enum.join(alarms, "; ")
          end
      },
      %{
        name: "backups",
        status:
          if(
            backups.latest_backup && backups.latest_backup["archive_exists"] &&
              backups.latest_backup["verified"] != false,
            do: :ok,
            else: :warn
          ),
        detail: backup_detail(backups)
      },
      %{
        name: "workspace",
        status: :ok,
        detail: Config.workspace_root()
      }
    ]

    checks
    |> maybe_filter_check_status(Keyword.get(opts, :status))
    |> maybe_filter_check_search(Keyword.get(opts, :search))
  end

  def telegram_status do
    diagnostics = telegram_delivery_diagnostics()

    case HydraX.Runtime.TelegramAdmin.enabled_telegram_config() ||
           List.first(HydraX.Runtime.TelegramAdmin.list_telegram_configs()) do
      nil ->
        %{
          channel: "telegram",
          configured: false,
          enabled: false,
          bot_username: nil,
          webhook_url: Config.telegram_webhook_url(),
          registered_at: nil,
          last_checked_at: nil,
          pending_update_count: 0,
          last_error: nil,
          default_agent_name: nil,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: diagnostics.gateway_events
        }

      config ->
        %{
          channel: "telegram",
          configured: true,
          enabled: config.enabled,
          bot_username: config.bot_username,
          webhook_url: config.webhook_url || Config.telegram_webhook_url(),
          registered_at: config.webhook_registered_at,
          last_checked_at: config.webhook_last_checked_at,
          pending_update_count: config.webhook_pending_update_count || 0,
          last_error: config.webhook_last_error,
          default_agent_name: config.default_agent && config.default_agent.name,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: diagnostics.gateway_events
        }
    end
  end

  def discord_status do
    diagnostics = channel_delivery_diagnostics("discord")

    case HydraX.Runtime.DiscordAdmin.enabled_discord_config() ||
           List.first(HydraX.Runtime.DiscordAdmin.list_discord_configs()) do
      nil ->
        %{
          channel: "discord",
          configured: false,
          enabled: false,
          binding: nil,
          default_agent_name: nil,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: recent_gateway_events("discord")
        }

      config ->
        %{
          channel: "discord",
          configured: true,
          enabled: config.enabled,
          binding: config.application_id,
          default_agent_name: config.default_agent && config.default_agent.name,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: recent_gateway_events("discord")
        }
    end
  end

  def slack_status do
    diagnostics = channel_delivery_diagnostics("slack")

    case HydraX.Runtime.SlackAdmin.enabled_slack_config() ||
           List.first(HydraX.Runtime.SlackAdmin.list_slack_configs()) do
      nil ->
        %{
          channel: "slack",
          configured: false,
          enabled: false,
          binding: nil,
          default_agent_name: nil,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: recent_gateway_events("slack")
        }

      config ->
        %{
          channel: "slack",
          configured: true,
          enabled: config.enabled,
          binding: "bot token configured",
          default_agent_name: config.default_agent && config.default_agent.name,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: recent_gateway_events("slack")
        }
    end
  end

  def webchat_status do
    diagnostics = channel_delivery_diagnostics("webchat")

    case HydraX.Runtime.WebchatAdmin.enabled_webchat_config() ||
           List.first(HydraX.Runtime.WebchatAdmin.list_webchat_configs()) do
      nil ->
        %{
          channel: "webchat",
          configured: false,
          enabled: false,
          binding: "/webchat",
          default_agent_name: nil,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: recent_gateway_events("webchat")
        }

      config ->
        %{
          channel: "webchat",
          configured: true,
          enabled: config.enabled,
          binding: "/webchat",
          default_agent_name: config.default_agent && config.default_agent.name,
          allow_anonymous_messages: config.allow_anonymous_messages,
          session_max_age_minutes: config.session_max_age_minutes,
          session_idle_timeout_minutes: config.session_idle_timeout_minutes,
          attachments_enabled: config.attachments_enabled,
          max_attachment_count: config.max_attachment_count,
          max_attachment_size_kb: config.max_attachment_size_kb,
          retryable_count: diagnostics.retryable_count,
          dead_letter_count: diagnostics.dead_letter_count,
          streaming_count: diagnostics.streaming_count,
          multipart_failure_count: diagnostics.multipart_failure_count,
          attachment_failure_count: diagnostics.attachment_failure_count,
          recent_failures: diagnostics.recent_failures,
          recent_streaming: diagnostics.recent_streaming,
          gateway_events: recent_gateway_events("webchat")
        }
    end
  end

  def channel_statuses do
    %{
      telegram: telegram_status(),
      discord: discord_status(),
      slack: slack_status(),
      webchat: webchat_status()
    }
  end

  def mcp_statuses do
    HydraX.Runtime.MCPServers.mcp_statuses()
  end

  def budget_status(agent_or_id \\ nil)
  def budget_status(%AgentProfile{} = agent), do: do_budget_status(agent)

  def budget_status(agent_id) when is_integer(agent_id),
    do: HydraX.Runtime.Agents.get_agent!(agent_id) |> do_budget_status()

  def budget_status(nil),
    do: do_budget_status(HydraX.Runtime.Agents.get_default_agent())

  def memory_triage_status(agent_or_id \\ nil)
  def memory_triage_status(%AgentProfile{} = agent), do: do_memory_triage_status(agent)

  def memory_triage_status(agent_id) when is_integer(agent_id),
    do: HydraX.Runtime.Agents.get_agent!(agent_id) |> do_memory_triage_status()

  def memory_triage_status(nil),
    do: do_memory_triage_status(HydraX.Runtime.Agents.get_default_agent())

  def provider_status do
    provider = HydraX.Runtime.Providers.enabled_provider()
    default_agent = HydraX.Runtime.Agents.get_default_agent()
    runtime = default_agent && HydraX.Runtime.Agents.agent_runtime_status(default_agent)

    route =
      default_agent &&
        HydraX.Runtime.Providers.effective_provider_route(default_agent.id, "channel")

    selected = (route && route.provider) || provider

    %{
      configured: not is_nil(selected),
      name: (selected && (selected.name || selected.kind)) || "mock fallback",
      kind: (selected && selected.kind) || "mock",
      model: selected && selected.model,
      route_source: (route && route.source) || if(provider, do: "global", else: "mock"),
      fallback_count: (route && length(route.fallbacks)) || 0,
      readiness: (runtime && runtime.readiness) || if(provider, do: "configured", else: "mock"),
      warmup_status: (runtime && runtime.warmup_status) || "n/a",
      capabilities: HydraX.Runtime.Providers.provider_capabilities(selected)
    }
  end

  def safety_status(opts \\ []) do
    counts = HydraX.Safety.recent_counts()
    statuses = HydraX.Safety.status_counts()
    limit = Keyword.get(opts, :limit, 12)
    offset = Keyword.get(opts, :offset, 0)
    level = Keyword.get(opts, :level)
    category = Keyword.get(opts, :category)
    status = Keyword.get(opts, :status)

    %{
      counts: %{
        info: Map.get(counts, "info", 0),
        warn: Map.get(counts, "warn", 0),
        error: Map.get(counts, "error", 0)
      },
      statuses: %{
        open: Map.get(statuses, "open", 0),
        acknowledged: Map.get(statuses, "acknowledged", 0),
        resolved: Map.get(statuses, "resolved", 0)
      },
      recent_events:
        HydraX.Safety.list_events(
          limit: limit,
          offset: offset,
          level: level,
          category: category,
          status: status
        ),
      categories: HydraX.Safety.categories()
    }
  end

  def operator_status do
    auth_events = Safety.list_events(category: "auth", limit: 40)
    audit = operator_auth_audit(auth_events)

    case Repo.get_by(OperatorSecret, scope: "control_plane") do
      nil ->
        %{
          configured: false,
          last_rotated_at: nil,
          password_age_days: nil,
          password_stale?: false,
          login_max_attempts: LoginThrottle.max_attempts(),
          login_window_seconds: LoginThrottle.window_seconds(),
          blocked_login_ips: LoginThrottle.summary().blocked_ips,
          session_max_age_seconds: HydraXWeb.OperatorAuth.session_max_age_seconds(),
          idle_timeout_seconds: HydraXWeb.OperatorAuth.idle_timeout_seconds(),
          recent_auth_window_seconds: HydraXWeb.OperatorAuth.recent_auth_window_seconds()
        }
        |> Map.merge(audit)

      secret ->
        age_days = password_age_days(secret.last_rotated_at)

        %{
          configured: true,
          last_rotated_at: secret.last_rotated_at,
          password_age_days: age_days,
          password_stale?: age_days >= 90,
          login_max_attempts: LoginThrottle.max_attempts(),
          login_window_seconds: LoginThrottle.window_seconds(),
          blocked_login_ips: LoginThrottle.summary().blocked_ips,
          session_max_age_seconds: HydraXWeb.OperatorAuth.session_max_age_seconds(),
          idle_timeout_seconds: HydraXWeb.OperatorAuth.idle_timeout_seconds(),
          recent_auth_window_seconds: HydraXWeb.OperatorAuth.recent_auth_window_seconds()
        }
        |> Map.merge(audit)
    end
  end

  def tool_status do
    policy = effective_policy_status().tool_policy

    %{
      workspace_list_enabled: policy.workspace_list_enabled,
      workspace_guard: policy.workspace_read_enabled,
      workspace_write_enabled: policy.workspace_write_enabled,
      url_guard: policy.http_fetch_enabled,
      browser_automation_enabled: policy.browser_automation_enabled,
      web_search_enabled: policy.web_search_enabled,
      shell_command_enabled: policy.shell_command_enabled,
      workspace_write_channels: policy.workspace_write_channels,
      http_fetch_channels: policy.http_fetch_channels,
      browser_automation_channels: policy.browser_automation_channels,
      web_search_channels: policy.web_search_channels,
      shell_command_channels: policy.shell_command_channels,
      shell_allowlist: policy.shell_allowlist,
      http_allowlist: policy.http_allowlist
    }
  end

  def autonomy_status do
    HydraX.Runtime.WorkItems.autonomy_status()
  end

  def control_policy_status do
    policy = effective_policy_status().control_policy

    %{
      require_recent_auth_for_sensitive_actions: policy.require_recent_auth_for_sensitive_actions,
      recent_auth_window_minutes: policy.recent_auth_window_minutes,
      interactive_delivery_channels: policy.interactive_delivery_channels,
      job_delivery_channels: policy.job_delivery_channels,
      ingest_roots: policy.ingest_roots
    }
  end

  def effective_policy_status(agent_id \\ nil, opts \\ []) do
    HydraX.Runtime.effective_policy(agent_id, opts)
  end

  def secret_storage_status do
    scopes = [
      summarize_secret_values("provider", provider_secret_values()),
      summarize_secret_values("telegram", telegram_secret_values()),
      summarize_secret_values("discord", discord_secret_values()),
      summarize_secret_values("slack", slack_secret_values())
    ]

    total_records = Enum.reduce(scopes, 0, &(&1.total_records + &2))
    encrypted_records = Enum.reduce(scopes, 0, &(&1.encrypted_records + &2))
    env_backed_records = Enum.reduce(scopes, 0, &(&1.env_backed_records + &2))
    unresolved_env_records = Enum.reduce(scopes, 0, &(&1.unresolved_env_records + &2))
    plaintext_records = Enum.reduce(scopes, 0, &(&1.plaintext_records + &2))
    protected_records = encrypted_records + env_backed_records

    posture =
      cond do
        plaintext_records > 0 -> "warning"
        unresolved_env_records > 0 -> "degraded"
        total_records == 0 -> "empty"
        true -> "hardened"
      end

    issues =
      []
      |> maybe_add_issue(
        plaintext_records > 0,
        "#{plaintext_records} plaintext records still stored"
      )
      |> maybe_add_issue(
        unresolved_env_records > 0,
        "#{unresolved_env_records} env references are unresolved at runtime"
      )
      |> maybe_add_issue(
        total_records == 0,
        "no persisted provider or channel secrets have been configured"
      )

    %{
      posture: posture,
      issues: issues,
      scopes: scopes,
      total_records: total_records,
      protected_records: protected_records,
      coverage_percent:
        if(total_records == 0, do: 100, else: round(protected_records * 100 / total_records)),
      encrypted_records: encrypted_records,
      env_backed_records: env_backed_records,
      resolved_env_records: env_backed_records - unresolved_env_records,
      unresolved_env_records: unresolved_env_records,
      plaintext_records: plaintext_records,
      key_source: Secrets.key_source()
    }
  end

  def observability_status do
    telemetry = HydraX.Telemetry.Store.snapshot()

    %{
      telemetry: telemetry,
      telemetry_summary: telemetry_summary(telemetry),
      scheduler: %{
        total_jobs: length(HydraX.Runtime.Jobs.list_scheduled_jobs(limit: 100)),
        recent_runs: HydraX.Runtime.Jobs.recent_job_runs(10)
      },
      autonomy: autonomy_status(),
      cluster: cluster_status(),
      coordination: coordination_status(),
      system: system_status(),
      backups: backup_status()
    }
  end

  def cluster_status do
    Cluster.status()
  end

  def coordination_status do
    HydraX.Runtime.Coordination.status()
  end

  def system_status do
    alarms =
      :alarm_handler.get_alarms()
      |> Enum.map(&format_alarm/1)

    %{
      alarms: alarms,
      database_path: Config.repo_database_path(),
      database_url: Config.repo_database_url(),
      persistence: Config.repo_persistence_status(),
      coordination: coordination_status()
    }
  end

  def readiness_report(opts \\ []) do
    tool_policy = HydraX.Runtime.Providers.effective_tool_policy()
    control_policy = control_policy_status()
    backup_root = Config.backup_root()
    telegram = telegram_status()
    discord = discord_status()
    slack = slack_status()
    webchat = webchat_status()
    backups = backup_status()
    public_url = Config.public_base_url()
    local_url? = local_public_url?(public_url)
    memory_status = memory_triage_status()
    secrets = secret_storage_status()
    default_agent = HydraX.Runtime.Agents.get_default_agent()

    default_agent_runtime =
      default_agent && HydraX.Runtime.Agents.agent_runtime_status(default_agent)

    default_agent_route =
      default_agent &&
        HydraX.Runtime.Providers.effective_provider_route(default_agent.id, "channel")

    operator = operator_status()
    cluster = cluster_status()
    coordination = coordination_status()
    autonomy = autonomy_status()

    items = [
      %{
        id: "operator_password",
        label: "Operator password configured",
        required: true,
        status: if(operator_password_configured?(), do: :ok, else: :warn),
        detail:
          if(operator_password_configured?(),
            do: "control plane requires login",
            else: "set a password on /setup before exposing the node"
          )
      },
      %{
        id: "operator_rotation",
        label: "Operator password rotated recently",
        required: false,
        status:
          cond do
            not operator.configured -> :warn
            operator.password_stale? -> :warn
            true -> :ok
          end,
        detail:
          cond do
            not operator.configured ->
              "set and rotate the control-plane password before public preview"

            operator.password_age_days == 0 ->
              "rotated today"

            operator.password_age_days ->
              "#{operator.password_age_days} days since last rotation"

            true ->
              "rotation timestamp unavailable"
          end
      },
      %{
        id: "operator_auth_flow",
        label: "Operator auth flow is clean",
        required: false,
        status:
          if(
            operator.recent_login_failure_count > 0 or
              operator.recent_rate_limited_count > 0 or
              operator.recent_session_expiry_count > 0,
            do: :warn,
            else: :ok
          ),
        detail: operator_auth_readiness_detail(operator)
      },
      %{
        id: "public_url",
        label: "Public URL points beyond localhost",
        required: true,
        status: if(local_url?, do: :warn, else: :ok),
        detail:
          if(local_url?,
            do: "HYDRA_X_PUBLIC_URL is still local: #{public_url}",
            else: public_url
          )
      },
      %{
        id: "backups",
        label: "Backups are being written",
        required: true,
        status:
          if(
            backups.latest_backup && backups.latest_backup["archive_exists"] &&
              backups.latest_backup["verified"] != false,
            do: :ok,
            else: :warn
          ),
        detail:
          case backups.latest_backup do
            nil ->
              "no backup manifest found in #{backup_root}"

            backup ->
              backup_readiness_detail(backup)
          end
      },
      (
        readiness_provider = HydraX.Runtime.Providers.enabled_provider()

        %{
          id: "provider",
          label: "Primary provider configured",
          required: false,
          status: if(readiness_provider, do: :ok, else: :warn),
          detail:
            case readiness_provider do
              nil -> "mock fallback only"
              p -> "#{p.kind}: #{p.model}"
            end
        }
      ),
      %{
        id: "default_agent_provider",
        label: "Default agent provider route warmed",
        required: false,
        status:
          case default_agent_runtime do
            %{readiness: "ready"} -> :ok
            %{readiness: "mock"} -> :warn
            %{readiness: "degraded"} -> :warn
            _ -> :warn
          end,
        detail:
          case {default_agent, default_agent_runtime, default_agent_route} do
            {nil, _, _} ->
              "no default agent configured"

            {agent, %{readiness: readiness} = runtime, route} ->
              provider_label =
                case route.provider do
                  nil -> "mock"
                  provider -> provider.name || provider.model || provider.kind
                end

              "#{agent.slug}: #{provider_label} via #{route.source}; runtime #{readiness}; warmup #{runtime.warmup_status}"
          end
      },
      %{
        id: "telegram",
        label: "Telegram ingress configured",
        required: false,
        status: if(telegram.configured and telegram.enabled, do: :ok, else: :warn),
        detail:
          cond do
            telegram.configured and telegram.enabled ->
              (telegram.bot_username && "@#{telegram.bot_username}") || "configured"

            telegram.configured ->
              "saved but disabled"

            true ->
              "not configured"
          end
      },
      %{
        id: "discord",
        label: "Discord ingress configured",
        required: false,
        status: if(discord.configured and discord.enabled, do: :ok, else: :warn),
        detail:
          cond do
            discord.configured and discord.enabled ->
              "configured#{agent_suffix(discord.default_agent_name)}"

            discord.configured ->
              "saved but disabled"

            true ->
              "not configured"
          end
      },
      %{
        id: "slack",
        label: "Slack ingress configured",
        required: false,
        status: if(slack.configured and slack.enabled, do: :ok, else: :warn),
        detail:
          cond do
            slack.configured and slack.enabled ->
              "configured#{agent_suffix(slack.default_agent_name)}"

            slack.configured ->
              "saved but disabled"

            true ->
              "not configured"
          end
      },
      %{
        id: "webchat",
        label: "Webchat ingress configured",
        required: false,
        status: if(webchat.configured and webchat.enabled, do: :ok, else: :warn),
        detail:
          cond do
            webchat.configured and webchat.enabled ->
              "configured#{agent_suffix(webchat.default_agent_name)} at /webchat · #{webchat_policy_detail(webchat)}"

            webchat.configured ->
              "saved but disabled"

            true ->
              "not configured"
          end
      },
      (
        readiness_jobs = HydraX.Runtime.Jobs.list_scheduled_jobs(limit: 5)

        %{
          id: "scheduler",
          label: "Scheduler has jobs",
          required: false,
          status: if(readiness_jobs == [], do: :warn, else: :ok),
          detail:
            case readiness_jobs do
              [] -> "no scheduled jobs configured"
              j -> "#{length(j)} jobs configured"
            end
        }
      ),
      %{
        id: "memory_conflicts",
        label: "Memory conflicts are triaged",
        required: false,
        status: if(Map.get(memory_status.counts, "conflicted", 0) > 0, do: :warn, else: :ok),
        detail:
          case Map.get(memory_status.counts, "conflicted", 0) do
            0 -> "no conflicted memories pending"
            count -> "#{count} conflicted memories need review"
          end
      },
      %{
        id: "autonomy_roles",
        label: "Autonomy roles configured",
        required: false,
        status: if(autonomy.autonomy_agent_count > 0, do: :ok, else: :warn),
        detail:
          if(
            autonomy.autonomy_agent_count > 0,
            do:
              "#{autonomy.autonomy_agent_count} autonomy-capable agents across #{map_size(autonomy.active_roles)} roles",
            else: "create at least one planner or researcher before enabling autonomous work"
          )
      },
      %{
        id: "tool_policy",
        label: "Tool policy reviewed",
        required: false,
        status:
          if(
            tool_policy.shell_command_enabled or tool_policy.http_allowlist != [] or
              tool_policy.workspace_write_enabled or tool_policy.browser_automation_enabled,
            do: :ok,
            else: :warn
          ),
        detail:
          "list #{enabled_text(tool_policy.workspace_list_enabled)}; read #{enabled_text(tool_policy.workspace_read_enabled)}; write #{enabled_text(tool_policy.workspace_write_enabled)} via #{describe_channels(tool_policy.workspace_write_channels)}; browser #{enabled_text(tool_policy.browser_automation_enabled)} via #{describe_channels(tool_policy.browser_automation_channels)}; search #{enabled_text(tool_policy.web_search_enabled)} via #{describe_channels(tool_policy.web_search_channels)}; shell #{enabled_text(tool_policy.shell_command_enabled)} via #{describe_channels(tool_policy.shell_command_channels)}; http via #{describe_channels(tool_policy.http_fetch_channels)} allowlist #{describe_allowlist(tool_policy.http_allowlist)}"
      },
      %{
        id: "control_policy",
        label: "Control policy reviewed",
        required: false,
        status: :ok,
        detail: control_policy_detail(control_policy)
      },
      %{
        id: "secrets",
        label: "Runtime secrets are encrypted at rest",
        required: false,
        status:
          if(secrets.plaintext_records > 0 or secrets.unresolved_env_records > 0,
            do: :warn,
            else: :ok
          ),
        detail: secret_detail(secrets)
      },
      %{
        id: "cluster",
        label: "Cluster posture matches configured persistence",
        required: false,
        status: if(cluster.enabled or cluster.multi_node_ready, do: :warn, else: :ok),
        detail: cluster_readiness_detail(cluster)
      },
      %{
        id: "coordination",
        label: "Coordination mode matches the persistence rollout",
        required: false,
        status: if(coordination.enabled, do: :warn, else: :ok),
        detail: coordination_readiness_detail(coordination)
      }
    ]

    items =
      items
      |> maybe_filter_readiness_required(Keyword.get(opts, :required_only, false))
      |> maybe_filter_readiness_status(Keyword.get(opts, :status))
      |> maybe_filter_readiness_search(Keyword.get(opts, :search))

    %{
      counts: readiness_counts(items),
      blockers: readiness_blockers(items),
      recommendations: readiness_recommendations(items),
      next_steps: readiness_next_steps(items),
      summary:
        if(Enum.any?(items, &(&1.required and &1.status != :ok)),
          do: :warn,
          else: :ok
        ),
      items: items
    }
  end

  def install_snapshot do
    public_url = Config.public_base_url()
    uri = URI.parse(public_url)

    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      public_url: public_url,
      phx_host: uri.host || "localhost",
      port: uri.port || default_port(uri.scheme),
      database_path: Config.repo_database_path(),
      database_url: Config.repo_database_url(),
      persistence: Config.repo_persistence_status(),
      coordination: coordination_status(),
      workspace_root: Config.workspace_root(),
      backup_root: Config.backup_root(),
      cluster: cluster_status(),
      http_allowlist: Config.http_allowlist(),
      shell_allowlist: Config.shell_allowlist(),
      readiness: readiness_report()
    }
  end

  def backup_status do
    root = Config.backup_root()
    manifests = HydraX.Backup.list_manifests(root)

    %{
      root: root,
      latest_backup: List.first(manifests),
      latest_verified_backup:
        Enum.find(manifests, &(&1["archive_exists"] && Map.get(&1, "verified") == true)),
      verified_count: Enum.count(manifests, &(Map.get(&1, "verified") == true)),
      verification_failed_count: Enum.count(manifests, &(Map.get(&1, "verified") == false)),
      unverified_count: Enum.count(manifests, &is_nil(Map.get(&1, "verified"))),
      recent_backups: Enum.take(manifests, 5)
    }
  end

  # -- Private helpers --

  defp operator_password_configured? do
    not is_nil(Repo.get_by(OperatorSecret, scope: "control_plane"))
  end

  defp password_age_days(nil), do: nil

  defp password_age_days(rotated_at) do
    rotated_at
    |> DateTime.diff(DateTime.utc_now(), :second)
    |> Kernel.*(-1)
    |> Kernel./(86_400)
    |> floor()
    |> max(0)
  end

  defp do_budget_status(agent) do
    policy = agent && HydraX.Budget.ensure_policy!(agent.id)

    if agent && policy do
      usage = HydraX.Budget.usage_snapshot(agent.id, nil)

      %{
        agent_name: agent.name,
        agent_id: agent.id,
        policy: policy,
        usage: usage,
        safety_events: HydraX.Safety.recent_events(agent.id, 10),
        recent_usage: HydraX.Budget.recent_usage(agent.id, 15)
      }
    else
      %{
        agent_name: nil,
        agent_id: nil,
        policy: nil,
        usage: nil,
        safety_events: [],
        recent_usage: []
      }
    end
  end

  defp do_memory_triage_status(nil) do
    %{
      agent_id: nil,
      agent_name: nil,
      counts: %{},
      recent_conflicts: [],
      embedding: HydraX.Memory.embedding_status(),
      ranked_memories: []
    }
  end

  defp do_memory_triage_status(agent) do
    %{
      agent_id: agent.id,
      agent_name: agent.name,
      counts: Memory.status_counts(agent_id: agent.id),
      recent_conflicts: Memory.list_memories(agent_id: agent.id, status: "conflicted", limit: 8),
      embedding: Memory.embedding_status(agent.id),
      ranked_memories: Memory.search_ranked(agent.id, "", 5, status: "active")
    }
  end

  defp telegram_delivery_diagnostics do
    diagnostics = channel_delivery_diagnostics("telegram")

    gateway_events =
      HydraX.Safety.list_events(category: "gateway", limit: 5)
      |> Enum.map(fn event ->
        %{
          id: event.id,
          message: event.message,
          level: event.level,
          inserted_at: event.inserted_at,
          conversation_id: event.conversation_id
        }
      end)

    %{
      retryable_count: diagnostics.retryable_count,
      dead_letter_count: diagnostics.dead_letter_count,
      streaming_count: diagnostics.streaming_count,
      multipart_failure_count: diagnostics.multipart_failure_count,
      attachment_failure_count: diagnostics.attachment_failure_count,
      recent_failures: diagnostics.recent_failures,
      recent_streaming: diagnostics.recent_streaming,
      gateway_events: gateway_events
    }
  end

  defp channel_delivery_diagnostics(channel) do
    conversations = HydraX.Runtime.Conversations.list_conversations(channel: channel, limit: 50)

    failed_conversations = Enum.filter(conversations, &failed_channel_delivery?/1)
    streaming_conversations = Enum.filter(conversations, &streaming_channel_delivery?/1)

    failures =
      failed_conversations
      |> Enum.take(5)
      |> Enum.map(&channel_delivery_entry/1)

    streaming =
      streaming_conversations
      |> Enum.take(5)
      |> Enum.map(&channel_delivery_entry/1)

    %{
      retryable_count: length(failed_conversations),
      dead_letter_count: Enum.count(failed_conversations, &dead_letter_channel_delivery?/1),
      streaming_count: length(streaming_conversations),
      multipart_failure_count: Enum.count(failed_conversations, &(delivery_chunk_count(&1) > 1)),
      attachment_failure_count:
        Enum.count(failed_conversations, &(conversation_attachment_count(&1) > 0)),
      recent_failures: failures,
      recent_streaming: streaming
    }
  end

  defp channel_delivery_entry(conversation) do
    delivery = last_delivery(conversation)
    payload = delivery_value(delivery, "formatted_payload") || %{}
    metadata = delivery_value(delivery, "metadata") || %{}
    provider_message_ids = delivery_value(delivery, "provider_message_ids") || []
    reply_context = delivery_value(delivery, "reply_context") || %{}

    %{
      id: conversation.id,
      title:
        conversation.title || conversation.external_ref || "#{conversation.channel} conversation",
      external_ref: conversation.external_ref,
      status: delivery_value(delivery, "status"),
      reason: delivery_value(delivery, "reason"),
      retry_count: delivery_value(delivery, "retry_count") || 0,
      updated_at: conversation.updated_at,
      next_retry_at: delivery_value(delivery, "next_retry_at"),
      dead_lettered_at: delivery_value(delivery, "dead_lettered_at"),
      chunk_count:
        delivery_value(delivery, "chunk_count") || delivery_value(payload, "chunk_count"),
      formatted_payload: payload,
      provider_message_id: delivery_value(delivery, "provider_message_id"),
      provider_message_ids_count: length(provider_message_ids),
      attachment_count: conversation_attachment_count(conversation),
      reply_context: reply_context,
      stream_message_id: delivery_value(reply_context, "stream_message_id"),
      transport: delivery_value(metadata, "transport"),
      transport_topic: delivery_value(metadata, "transport_topic"),
      transport_error: delivery_value(metadata, "transport_error")
    }
  end

  defp recent_gateway_events(channel) do
    HydraX.Telemetry.Store.snapshot()
    |> Map.get(:recent_events, [])
    |> Enum.filter(fn event ->
      event.namespace == "gateway" and event.bucket == channel
    end)
    |> Enum.take(5)
  end

  defp failed_channel_delivery?(conversation) do
    case last_delivery(conversation) do
      %{"status" => "failed"} -> true
      %{status: "failed"} -> true
      %{"status" => "dead_letter"} -> true
      %{status: "dead_letter"} -> true
      _ -> false
    end
  end

  defp dead_letter_channel_delivery?(conversation) do
    case last_delivery(conversation) do
      %{"status" => "dead_letter"} -> true
      %{status: "dead_letter"} -> true
      _ -> false
    end
  end

  defp streaming_channel_delivery?(conversation) do
    case last_delivery(conversation) do
      %{"status" => "streaming"} -> true
      %{status: "streaming"} -> true
      _ -> false
    end
  end

  defp delivery_chunk_count(conversation) do
    delivery = last_delivery(conversation)
    payload = delivery_value(delivery, "formatted_payload") || %{}

    delivery_value(delivery, "chunk_count") || delivery_value(payload, "chunk_count") || 0
  end

  defp conversation_attachment_count(conversation) do
    if Ecto.assoc_loaded?(conversation.turns) do
      Enum.reduce(conversation.turns || [], 0, fn turn, acc ->
        metadata = turn.metadata || %{}
        attachments = metadata["attachments"] || metadata[:attachments] || []
        acc + length(attachments)
      end)
    else
      0
    end
  end

  defp channel_health_detail(statuses) do
    statuses
    |> Map.values()
    |> Enum.map(fn status ->
      cond do
        status.configured and status.enabled ->
          "#{status.channel}: enabled#{agent_suffix(status.default_agent_name)}"

        status.configured ->
          "#{status.channel}: disabled"

        true ->
          "#{status.channel}: not configured"
      end
    end)
    |> Enum.join(" · ")
  end

  defp mcp_health_detail([]), do: "no MCP servers configured"

  defp mcp_health_detail(statuses) do
    statuses
    |> Enum.map(fn status ->
      "#{status.name} (#{status.transport}): #{if(status.status == :ok, do: "healthy", else: "warn")}#{if(status.enabled, do: "", else: " disabled")}"
    end)
    |> Enum.join(" · ")
  end

  defp cluster_detail(cluster) do
    base =
      "#{cluster.mode} · node #{cluster.node_id} · nodes #{cluster.node_count} · persistence #{cluster.persistence}"

    cond do
      cluster.enabled and cluster.leader_node and cluster.persistence_backend == "postgres" ->
        "#{base} · leader #{cluster.leader_node} · PostgreSQL is in place, but ownership/routing failover is still pending"

      cluster.enabled and cluster.leader_node ->
        "#{base} · leader #{cluster.leader_node} · PostgreSQL migration still required for real multi-node"

      cluster.enabled and cluster.persistence_backend == "postgres" ->
        "#{base} · no leader registered yet · PostgreSQL is in place, but ownership/routing failover is still pending"

      cluster.enabled ->
        "#{base} · no leader registered yet · PostgreSQL migration still required for real multi-node"

      cluster.persistence_backend == "postgres" ->
        "#{base} · persistence is ready for multi-node follow-up work; federation intentionally disabled"

      true ->
        "#{base} · federation intentionally disabled"
    end
  end

  defp database_health_detail(%{backend: "postgres", target: target}) do
    "PostgreSQL repo configured#{format_persistence_target(target)}"
  end

  defp database_health_detail(%{target: target}) do
    "SQLite repo online#{format_persistence_target(target)}"
  end

  defp cluster_readiness_detail(cluster) do
    cond do
      cluster.enabled and cluster.persistence_backend == "postgres" ->
        "cluster awareness is enabled with PostgreSQL backing, but ownership, routing, and failover are still pending"

      cluster.enabled ->
        "cluster awareness is enabled, but SQLite still blocks production multi-node failover"

      cluster.persistence_backend == "postgres" ->
        "single-node mode is active; PostgreSQL persistence is configured for the post-preview architecture rollout"

      true ->
        "single-node mode is active; enable clustering only after moving coordination to PostgreSQL"
    end
  end

  defp coordination_detail(coordination) do
    case coordination.mode do
      "database_leases" ->
        "database leases active; scheduler owner #{coordination.scheduler_owner || "none"}; active leases #{coordination.lease_count}"

      _ ->
        "local single-node ownership only"
    end
  end

  defp coordination_readiness_detail(coordination) do
    case coordination.mode do
      "database_leases" ->
        "database lease coordination is active; distributed ownership and failover logic are still pending"

      _ ->
        "coordination remains local-only until PostgreSQL-backed ownership is enabled"
    end
  end

  defp autonomy_detail(autonomy) do
    completed = Map.get(autonomy.counts, "completed", 0)
    running = Map.get(autonomy.counts, "running", 0) + Map.get(autonomy.counts, "claimed", 0)

    "agents #{autonomy.autonomy_agent_count}; running #{running}; completed #{completed}; overdue #{autonomy.overdue_count}; pending review #{autonomy.pending_review_count}"
  end

  defp format_persistence_target(nil), do: ""
  defp format_persistence_target(target), do: " (#{target})"

  defp agent_suffix(nil), do: ""
  defp agent_suffix(name), do: " -> #{name}"

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery] || %{}
  end

  defp delivery_value(map, key) when is_map(map) do
    Map.get(map, key) ||
      case key do
        "formatted_payload" -> Map.get(map, :formatted_payload)
        "provider_message_ids" -> Map.get(map, :provider_message_ids)
        "reply_context" -> Map.get(map, :reply_context)
        "status" -> Map.get(map, :status)
        "reason" -> Map.get(map, :reason)
        "retry_count" -> Map.get(map, :retry_count)
        "next_retry_at" -> Map.get(map, :next_retry_at)
        "dead_lettered_at" -> Map.get(map, :dead_lettered_at)
        "chunk_count" -> Map.get(map, :chunk_count)
        _ -> nil
      end
  end

  defp delivery_value(_map, _key), do: nil

  defp tool_detail(tool_status) do
    shell = Enum.join(tool_status.shell_allowlist, ", ")

    http =
      case tool_status.http_allowlist do
        [] -> "public hosts"
        hosts -> Enum.join(hosts, ", ")
      end

    "workspace list #{enabled_text(tool_status.workspace_list_enabled)}; workspace read #{enabled_text(tool_status.workspace_guard)}; workspace write/patch #{enabled_text(tool_status.workspace_write_enabled)} via #{describe_channels(tool_status.workspace_write_channels)}; browser automation #{enabled_text(tool_status.browser_automation_enabled)} via #{describe_channels(tool_status.browser_automation_channels)}; web search #{enabled_text(tool_status.web_search_enabled)} via #{describe_channels(tool_status.web_search_channels)}; http fetch #{enabled_text(tool_status.url_guard)} via #{describe_channels(tool_status.http_fetch_channels)}; shell #{enabled_text(tool_status.shell_command_enabled)} via #{describe_channels(tool_status.shell_command_channels)}; shell allowlist: #{shell}; http allowlist: #{http}"
  end

  defp control_policy_detail(control_policy) do
    "recent auth #{if(control_policy.require_recent_auth_for_sensitive_actions, do: "required", else: "optional")} within #{control_policy.recent_auth_window_minutes}m; interactive delivery via #{describe_channels(control_policy.interactive_delivery_channels)}; job delivery via #{describe_channels(control_policy.job_delivery_channels)}; ingest roots #{describe_allowlist(control_policy.ingest_roots)}"
  end

  defp effective_policy_detail(policy) do
    tool_summary =
      policy.tools
      |> Enum.map_join(", ", fn tool ->
        channels =
          case tool.channels do
            :all -> "all"
            values -> describe_channels(values)
          end

        "#{tool.tool_name}=#{enabled_text(tool.enabled?)}(#{channels})"
      end)

    route =
      "#{policy.routing.provider_name} via #{policy.routing.source} fallback=#{describe_channels(policy.routing.fallback_names)}"

    workload =
      case policy.routing.workload do
        %{pressure: pressure, applied?: applied?, reason: reason} ->
          "workload #{pressure}/#{if(applied?, do: "shifted", else: "steady")} #{reason}"

        _ ->
          "workload steady"
      end

    "auth #{if(policy.auth.recent_auth_required, do: "required", else: "optional")} within #{policy.auth.recent_auth_window_minutes}m; interactive #{describe_channels(policy.deliveries.interactive_channels)}; jobs #{describe_channels(policy.deliveries.job_channels)}; ingest #{describe_allowlist(policy.ingest.roots)}; route #{route}; #{workload}; tools #{tool_summary}"
  end

  defp secret_detail(secrets) do
    scopes =
      secrets.scopes
      |> Enum.filter(&(&1.total_records > 0))
      |> Enum.map_join(", ", fn scope ->
        "#{scope.scope} #{scope.protected_records}/#{scope.total_records}"
      end)

    "posture #{secrets.posture}; protected #{secrets.protected_records}/#{secrets.total_records} (#{secrets.coverage_percent}%); encrypted #{secrets.encrypted_records}; env-backed #{secrets.env_backed_records}; unresolved env #{secrets.unresolved_env_records}; plaintext #{secrets.plaintext_records}; key source #{secrets.key_source}#{if(scopes == "", do: "", else: "; scopes #{scopes}")}"
  end

  defp operator_detail(operator) do
    base =
      case operator do
        %{
          configured: true,
          last_rotated_at: rotated_at,
          password_stale?: true,
          password_age_days: age
        }
        when not is_nil(rotated_at) ->
          "operator password set; rotated #{Calendar.strftime(rotated_at, "%Y-%m-%d %H:%M UTC")}; age #{age} days; recent-auth window #{div(operator.recent_auth_window_seconds, 60)}m"

        %{configured: true, last_rotated_at: rotated_at} when not is_nil(rotated_at) ->
          "operator password set; rotated #{Calendar.strftime(rotated_at, "%Y-%m-%d %H:%M UTC")}; recent-auth window #{div(operator.recent_auth_window_seconds, 60)}m"

        %{configured: true} ->
          "operator password set; recent-auth window #{div(operator.recent_auth_window_seconds, 60)}m"

        _ ->
          "control plane open until operator password is set"
      end

    audit =
      "last24h ok #{operator.recent_login_success_count}; failed #{operator.recent_login_failure_count}; reauth blocks #{operator.recent_reauth_block_count}; expiries #{operator.recent_session_expiry_count}"

    [base, audit] |> Enum.join("; ")
  end

  defp operator_auth_readiness_detail(operator) do
    [
      "sign-ins #{operator.recent_login_success_count}",
      "failed logins #{operator.recent_login_failure_count}",
      "rate limits #{operator.recent_rate_limited_count}",
      "reauth blocks #{operator.recent_reauth_block_count}",
      "session expiries #{operator.recent_session_expiry_count}",
      operator.last_session_expired_reason &&
        "last expiry #{operator.last_session_expired_reason}",
      operator.last_login_at && "last sign-in #{format_datetime(operator.last_login_at)}"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join("; ")
  end

  defp operator_auth_audit(events) do
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)

    recent_events =
      Enum.filter(events, fn event ->
        DateTime.compare(event.inserted_at, cutoff) in [:gt, :eq]
      end)

    %{
      audit_window_hours: 24,
      recent_login_success_count: count_auth_events(recent_events, "Operator login succeeded"),
      recent_login_failure_count: count_auth_events(recent_events, "Operator login failed"),
      recent_rate_limited_count:
        count_auth_events(recent_events, "Blocked operator login due to rate limit"),
      recent_reauth_block_count:
        count_auth_events(recent_events, "Blocked sensitive action pending re-authentication"),
      recent_session_expiry_count: count_auth_events(recent_events, "Operator session expired"),
      last_login_at: latest_auth_event_at(events, "Operator login succeeded"),
      last_logout_at: latest_auth_event_at(events, "Operator logged out"),
      last_login_failure_at: latest_auth_event_at(events, "Operator login failed"),
      last_rate_limited_at:
        latest_auth_event_at(events, "Blocked operator login due to rate limit"),
      last_sensitive_action_block_at:
        latest_auth_event_at(events, "Blocked sensitive action pending re-authentication"),
      last_session_expired_at: latest_auth_event_at(events, "Operator session expired"),
      last_session_expired_reason:
        latest_auth_event_metadata(events, "Operator session expired", "expired_by"),
      recent_events: Enum.map(Enum.take(events, 6), &operator_auth_event_entry/1)
    }
  end

  defp operator_auth_event_entry(event) do
    metadata = event.metadata || %{}

    %{
      id: event.id,
      level: event.level,
      message: event.message,
      inserted_at: event.inserted_at,
      expired_by: metadata["expired_by"] || metadata[:expired_by],
      reauth?: metadata["reauth?"] || metadata[:reauth?] || false,
      ip: metadata["ip"] || metadata[:ip]
    }
  end

  defp latest_auth_event_at(events, message) do
    events
    |> Enum.find(&(&1.message == message))
    |> case do
      nil -> nil
      event -> event.inserted_at
    end
  end

  defp latest_auth_event_metadata(events, message, key) do
    events
    |> Enum.find(&(&1.message == message))
    |> case do
      %{metadata: metadata} when is_map(metadata) -> metadata[key] || metadata[:expired_by]
      _ -> nil
    end
  end

  defp count_auth_events(events, message) do
    Enum.count(events, &(&1.message == message))
  end

  defp summarize_secret_values(scope, values) do
    values =
      Enum.filter(values, &(Helpers.blank_to_nil(&1) not in [nil, ""]))

    encrypted_records = Enum.count(values, &Secrets.encrypted?/1)
    env_backed_records = Enum.count(values, &Secrets.env_reference?/1)
    unresolved_env_records = Enum.count(values, &Secrets.unresolved_env_reference?/1)

    %{
      scope: scope,
      total_records: length(values),
      protected_records: encrypted_records + env_backed_records,
      encrypted_records: encrypted_records,
      env_backed_records: env_backed_records,
      unresolved_env_records: unresolved_env_records,
      plaintext_records:
        Enum.count(values, fn value ->
          not Secrets.encrypted?(value) and not Secrets.env_reference?(value)
        end)
    }
  end

  defp maybe_add_issue(issues, true, message), do: issues ++ [message]
  defp maybe_add_issue(issues, false, _message), do: issues

  defp backup_detail(backups) do
    case backups.latest_backup do
      nil ->
        "no backup manifests found in #{backups.root}"

      backup ->
        [
          backup_readiness_detail(backup),
          "verified #{backups.verified_count}",
          if(backups.verification_failed_count > 0,
            do: "failed #{backups.verification_failed_count}"
          ),
          if(backups.unverified_count > 0, do: "pending #{backups.unverified_count}")
        ]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join("; ")
    end
  end

  defp backup_readiness_detail(backup) do
    mode = get_in(backup, ["persistence", "backup_mode"]) || "bundled_database"

    cond do
      not backup["archive_exists"] ->
        "archive missing for #{backup["archive_path"]}"

      backup["verified"] == false ->
        "latest backup #{backup["archive_path"]} failed verification"

      backup["verified"] == true ->
        "latest backup #{backup["archive_path"]} verified#{backup_mode_suffix(mode)}"

      true ->
        "latest backup #{backup["archive_path"]} not yet verified#{backup_mode_suffix(mode)}"
    end
  end

  defp backup_mode_suffix("external_database"),
    do: " (PostgreSQL reference only; external DB backup still required)"

  defp backup_mode_suffix(_mode), do: ""

  defp readiness_counts(items) do
    %{
      total: length(items),
      ok: Enum.count(items, &(&1.status == :ok)),
      warn: Enum.count(items, &(&1.status == :warn)),
      required_warn: Enum.count(items, &(&1.required and &1.status == :warn)),
      recommended_warn: Enum.count(items, &(!&1.required and &1.status == :warn))
    }
  end

  defp readiness_blockers(items) do
    items
    |> Enum.filter(&(&1.required and &1.status == :warn))
    |> Enum.map(&%{id: &1.id, label: &1.label, detail: &1.detail})
  end

  defp readiness_recommendations(items) do
    items
    |> Enum.filter(&(!&1.required and &1.status == :warn))
    |> Enum.map(&%{id: &1.id, label: &1.label, detail: &1.detail})
  end

  defp readiness_next_steps(items) do
    items
    |> Enum.filter(&(&1.status == :warn))
    |> Enum.take(5)
    |> Enum.map(fn item ->
      prefix = if item.required, do: "Required", else: "Recommended"
      "#{prefix}: #{item.label} - #{item.detail}"
    end)
  end

  defp provider_secret_values do
    Repo.all(from(provider in ProviderConfig, select: provider.api_key))
  end

  defp telegram_secret_values do
    Repo.all(
      from(config in TelegramConfig,
        select: [config.bot_token, config.webhook_secret]
      )
    )
    |> List.flatten()
  end

  defp discord_secret_values do
    Repo.all(
      from(config in DiscordConfig,
        select: [config.bot_token, config.webhook_secret]
      )
    )
    |> List.flatten()
  end

  defp slack_secret_values do
    Repo.all(
      from(config in SlackConfig,
        select: [config.bot_token, config.signing_secret]
      )
    )
    |> List.flatten()
  end

  defp describe_channels([]), do: "none"
  defp describe_channels(channels), do: Enum.join(channels, ", ")

  defp provider_health_detail(provider, nil, _runtime, _route) do
    provider_label = (provider && "#{provider.kind}: #{provider.model}") || "mock fallback"
    capabilities = provider_capability_summary(provider)
    [provider_label, capabilities] |> Enum.join(" · ")
  end

  defp provider_health_detail(provider, agent, runtime, route) do
    provider_label =
      case route && route.provider do
        nil -> (provider && "#{provider.kind}: #{provider.model}") || "mock fallback"
        selected -> "#{selected.name || selected.kind}: #{selected.model}"
      end

    capabilities = provider_capability_summary((route && route.provider) || provider)

    "#{provider_label} -> #{agent.slug} (#{runtime.readiness}/#{runtime.warmup_status}) · #{capabilities}"
  end

  defp provider_capability_summary(provider) do
    HydraX.Runtime.Providers.provider_capabilities(provider)
    |> Enum.filter(fn {_key, value} -> value end)
    |> Enum.map(fn {key, _value} -> key |> to_string() |> String.replace("_", "-") end)
    |> case do
      [] -> "capabilities none"
      values -> "capabilities " <> Enum.join(values, ", ")
    end
  end

  defp telemetry_summary(telemetry) do
    %{
      provider: summarize_telemetry_namespace(telemetry.provider),
      budget: summarize_telemetry_namespace(telemetry.budget),
      tool: summarize_telemetry_namespace(telemetry.tool),
      gateway: summarize_telemetry_namespace(telemetry.gateway),
      scheduler: summarize_telemetry_namespace(telemetry.scheduler)
    }
  end

  defp summarize_telemetry_namespace(namespace) when map_size(namespace) == 0 do
    %{total: 0, success: 0, error: 0, warn: 0, unknown: 0}
  end

  defp summarize_telemetry_namespace(namespace) do
    counts =
      Enum.reduce(namespace, %{}, fn
        {_bucket, statuses}, acc when is_map(statuses) ->
          Enum.reduce(statuses, acc, fn {status, count}, nested ->
            Map.update(nested, status, count, &(&1 + count))
          end)

        {status, count}, acc when is_integer(count) ->
          Map.update(acc, status, count, &(&1 + count))
      end)

    %{
      total: Enum.reduce(Map.values(counts), 0, &(&1 + &2)),
      success: Map.get(counts, "ok", 0) + Map.get(counts, "success", 0),
      error: Map.get(counts, "error", 0),
      warn: Map.get(counts, "warn", 0),
      unknown: Map.get(counts, "unknown", 0)
    }
  end

  defp enabled_text(true), do: "enabled"
  defp enabled_text(false), do: "disabled"

  defp describe_allowlist([]), do: "public hosts"
  defp describe_allowlist(hosts), do: Enum.join(hosts, ", ")

  defp default_port("https"), do: 443
  defp default_port(_scheme), do: 4000

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
      _ -> value
    end
  end

  defp webchat_policy_detail(webchat) do
    identity =
      if webchat.allow_anonymous_messages do
        "anonymous ok"
      else
        "identity required"
      end

    attachments =
      if webchat.attachments_enabled do
        "attachments #{webchat.max_attachment_count}x#{webchat.max_attachment_size_kb}KB"
      else
        "attachments disabled"
      end

    "#{identity} · max #{webchat.session_max_age_minutes}m · idle #{webchat.session_idle_timeout_minutes}m · #{attachments}"
  end

  defp format_alarm({:system_memory_high_watermark, _details}),
    do: "system memory high watermark"

  defp format_alarm({{:disk_almost_full, path}, _details}),
    do: "disk almost full at #{List.to_string(path)}"

  defp format_alarm({alarm, _details}), do: inspect(alarm)
  defp format_alarm(alarm), do: inspect(alarm)

  defp local_public_url?(url) do
    case URI.parse(url) do
      %URI{host: host} when host in [nil, "", "localhost", "127.0.0.1"] -> true
      %URI{host: host} when is_binary(host) -> String.ends_with?(host, ".local")
      _ -> true
    end
  end

  # -- Filter helpers --

  defp maybe_filter_check_status(checks, nil), do: checks
  defp maybe_filter_check_status(checks, ""), do: checks

  defp maybe_filter_check_status(checks, status) do
    Enum.filter(checks, &(Atom.to_string(&1.status) == to_string(status)))
  end

  defp maybe_filter_check_search(checks, nil), do: checks
  defp maybe_filter_check_search(checks, ""), do: checks

  defp maybe_filter_check_search(checks, search) do
    downcased = String.downcase(search)

    Enum.filter(checks, fn check ->
      String.contains?(String.downcase(check.name), downcased) or
        String.contains?(String.downcase(check.detail), downcased)
    end)
  end

  defp maybe_filter_readiness_required(items, true), do: Enum.filter(items, & &1.required)
  defp maybe_filter_readiness_required(items, _), do: items

  defp maybe_filter_readiness_status(items, nil), do: items
  defp maybe_filter_readiness_status(items, ""), do: items

  defp maybe_filter_readiness_status(items, status) do
    Enum.filter(items, &(Atom.to_string(&1.status) == to_string(status)))
  end

  defp maybe_filter_readiness_search(items, nil), do: items
  defp maybe_filter_readiness_search(items, ""), do: items

  defp maybe_filter_readiness_search(items, search) do
    downcased = String.downcase(search)

    Enum.filter(items, fn item ->
      String.contains?(String.downcase(item.label), downcased) or
        String.contains?(String.downcase(item.detail), downcased)
    end)
  end

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false
end
