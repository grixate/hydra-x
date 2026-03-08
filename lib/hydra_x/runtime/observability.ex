defmodule HydraX.Runtime.Observability do
  @moduledoc """
  Health snapshots, readiness reports, system status, and observability aggregation.
  """

  alias HydraX.Config
  alias HydraX.Memory

  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, OperatorSecret}

  def health_snapshot(opts \\ []) do
    provider = HydraX.Runtime.Providers.enabled_provider()
    default_agent = HydraX.Runtime.Agents.get_default_agent()
    budget_policy = default_agent && HydraX.Budget.ensure_policy!(default_agent.id)
    memory_status = memory_triage_status(default_agent)
    safety_counts = HydraX.Safety.recent_counts()
    system = system_status()
    backups = backup_status()
    safety_errors = Map.get(safety_counts, "error", 0)
    safety_warnings = Map.get(safety_counts, "warn", 0)

    agents = HydraX.Runtime.Agents.list_agents()
    telegram_config = HydraX.Runtime.TelegramAdmin.enabled_telegram_config()

    checks = [
      %{name: "database", status: :ok, detail: "SQLite repo online"},
      %{
        name: "agents",
        status: if(agents == [], do: :warn, else: :ok),
        detail: "#{length(agents)} configured"
      },
      %{
        name: "providers",
        status: if(provider, do: :ok, else: :warn),
        detail: (provider && "#{provider.kind}: #{provider.model}") || "mock fallback"
      },
      %{
        name: "auth",
        status: if(operator_password_configured?(), do: :ok, else: :warn),
        detail:
          case operator_status() do
            %{configured: true, last_rotated_at: rotated_at} when not is_nil(rotated_at) ->
              "operator password set; rotated #{Calendar.strftime(rotated_at, "%Y-%m-%d %H:%M UTC")}"

            %{configured: true} ->
              "operator password set"

            _ ->
              "control plane open until operator password is set"
          end
      },
      %{
        name: "telegram",
        status: if(telegram_config, do: :ok, else: :warn),
        detail:
          case telegram_config do
            %{bot_username: username, default_agent: %{name: agent_name}}
            when is_binary(username) and username != "" ->
              "@#{username} -> #{agent_name}"

            %{default_agent: %{name: agent_name}} ->
              "configured -> #{agent_name}"

            nil ->
              "not configured"
          end
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
          "active #{Map.get(memory_status.counts, "active", 0)}; conflicted #{Map.get(memory_status.counts, "conflicted", 0)}; superseded #{Map.get(memory_status.counts, "superseded", 0)}"
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
        name: "tools",
        status: :ok,
        detail: tool_detail(tool_status())
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
          if(backups.latest_backup && backups.latest_backup["archive_exists"],
            do: :ok,
            else: :warn
          ),
        detail:
          case backups.latest_backup do
            nil ->
              "no backup manifests found in #{backups.root}"

            backup ->
              if backup["archive_exists"] do
                "latest backup #{backup["archive_path"]}"
              else
                "latest backup archive missing for #{backup["archive_path"]}"
              end
          end
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
          recent_failures: diagnostics.recent_failures,
          gateway_events: diagnostics.gateway_events
        }

      config ->
        %{
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
          recent_failures: diagnostics.recent_failures,
          gateway_events: diagnostics.gateway_events
        }
    end
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
    case Repo.get_by(OperatorSecret, scope: "control_plane") do
      nil ->
        %{configured: false, last_rotated_at: nil}

      secret ->
        %{configured: true, last_rotated_at: secret.last_rotated_at}
    end
  end

  def tool_status do
    policy = HydraX.Runtime.Providers.effective_tool_policy()

    %{
      workspace_guard: policy.workspace_read_enabled,
      url_guard: policy.http_fetch_enabled,
      shell_command_enabled: policy.shell_command_enabled,
      shell_allowlist: policy.shell_allowlist,
      http_allowlist: policy.http_allowlist
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
      system: system_status(),
      backups: backup_status()
    }
  end

  def system_status do
    alarms =
      :alarm_handler.get_alarms()
      |> Enum.map(&format_alarm/1)

    %{
      alarms: alarms,
      database_path: Config.repo_database_path()
    }
  end

  def readiness_report(opts \\ []) do
    tool_policy = HydraX.Runtime.Providers.effective_tool_policy()
    backup_root = Config.backup_root()
    telegram = telegram_status()
    backups = backup_status()
    public_url = Config.public_base_url()
    local_url? = local_public_url?(public_url)
    memory_status = memory_triage_status()

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
          if(backups.latest_backup && backups.latest_backup["archive_exists"],
            do: :ok,
            else: :warn
          ),
        detail:
          case backups.latest_backup do
            nil ->
              "no backup manifest found in #{backup_root}"

            backup ->
              if backup["archive_exists"] do
                backup["archive_path"]
              else
                "archive missing for #{backup["archive_path"]}"
              end
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
        id: "tool_policy",
        label: "Tool policy reviewed",
        required: false,
        status:
          if(tool_policy.shell_command_enabled or tool_policy.http_allowlist != [],
            do: :ok,
            else: :warn
          ),
        detail:
          "shell #{enabled_text(tool_policy.shell_command_enabled)}; http allowlist #{describe_allowlist(tool_policy.http_allowlist)}"
      }
    ]

    items =
      items
      |> maybe_filter_readiness_required(Keyword.get(opts, :required_only, false))
      |> maybe_filter_readiness_status(Keyword.get(opts, :status))
      |> maybe_filter_readiness_search(Keyword.get(opts, :search))

    %{
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
      workspace_root: Config.workspace_root(),
      backup_root: Config.backup_root(),
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
      recent_backups: Enum.take(manifests, 5)
    }
  end

  # -- Private helpers --

  defp operator_password_configured? do
    not is_nil(Repo.get_by(OperatorSecret, scope: "control_plane"))
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
    %{agent_id: nil, agent_name: nil, counts: %{}, recent_conflicts: []}
  end

  defp do_memory_triage_status(agent) do
    %{
      agent_id: agent.id,
      agent_name: agent.name,
      counts: Memory.status_counts(agent_id: agent.id),
      recent_conflicts: Memory.list_memories(agent_id: agent.id, status: "conflicted", limit: 8)
    }
  end

  defp telegram_delivery_diagnostics do
    telegram_conversations =
      HydraX.Runtime.Conversations.list_conversations(channel: "telegram", limit: 50)

    recent_failures =
      telegram_conversations
      |> Enum.filter(&failed_telegram_delivery?/1)
      |> Enum.take(5)
      |> Enum.map(fn conversation ->
        delivery = last_delivery(conversation)

        %{
          id: conversation.id,
          title: conversation.title || conversation.external_ref || "telegram conversation",
          external_ref: conversation.external_ref,
          reason: delivery_value(delivery, "reason"),
          retry_count: delivery_value(delivery, "retry_count") || 0,
          updated_at: conversation.updated_at
        }
      end)

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
      retryable_count: Enum.count(telegram_conversations, &failed_telegram_delivery?/1),
      recent_failures: recent_failures,
      gateway_events: gateway_events
    }
  end

  defp failed_telegram_delivery?(conversation) do
    delivery = last_delivery(conversation)

    delivery_value(delivery, "channel") == "telegram" and
      delivery_value(delivery, "status") == "failed"
  end

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery] || %{}
  end

  defp delivery_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp delivery_value(_map, _key), do: nil

  defp tool_detail(tool_status) do
    shell = Enum.join(tool_status.shell_allowlist, ", ")

    http =
      case tool_status.http_allowlist do
        [] -> "public hosts"
        hosts -> Enum.join(hosts, ", ")
      end

    "workspace read #{enabled_text(tool_status.workspace_guard)}; http fetch #{enabled_text(tool_status.url_guard)}; shell #{enabled_text(tool_status.shell_command_enabled)}; shell allowlist: #{shell}; http allowlist: #{http}"
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
end
