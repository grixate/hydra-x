defmodule HydraX.Runtime.EffectivePolicy do
  @moduledoc """
  Consolidated policy resolution for tools, delivery, ingest, auth freshness,
  and provider routing.
  """

  alias HydraX.Runtime.{ControlPolicies, Jobs, Providers}

  @tool_specs %{
    "workspace_list" => %{enabled_field: :workspace_list_enabled, channels_field: nil},
    "workspace_read" => %{enabled_field: :workspace_read_enabled, channels_field: nil},
    "workspace_write" => %{
      enabled_field: :workspace_write_enabled,
      channels_field: :workspace_write_channels
    },
    "workspace_patch" => %{
      enabled_field: :workspace_write_enabled,
      channels_field: :workspace_write_channels
    },
    "http_fetch" => %{enabled_field: :http_fetch_enabled, channels_field: :http_fetch_channels},
    "browser_automation" => %{
      enabled_field: :browser_automation_enabled,
      channels_field: :browser_automation_channels
    },
    "web_search" => %{enabled_field: :web_search_enabled, channels_field: :web_search_channels},
    "shell_command" => %{
      enabled_field: :shell_command_enabled,
      channels_field: :shell_command_channels
    }
  }
  @background_processes ~w(scheduler compactor cortex)

  def effective_policy(agent_id \\ nil, opts \\ []) do
    tool_policy = Providers.effective_tool_policy(agent_id)
    control_policy = ControlPolicies.effective_control_policy(agent_id)
    process_type = Keyword.get(opts, :process_type, "channel")
    route = effective_provider_route(agent_id, process_type, opts)

    %{
      agent_id: agent_id,
      process_type: process_type,
      tool_policy: tool_policy,
      control_policy: control_policy,
      tools: tool_access(tool_policy),
      auth: %{
        recent_auth_required: control_policy.require_recent_auth_for_sensitive_actions,
        recent_auth_window_minutes: control_policy.recent_auth_window_minutes
      },
      deliveries: %{
        interactive_channels: control_policy.interactive_delivery_channels,
        job_channels: control_policy.job_delivery_channels
      },
      ingest: %{
        roots: control_policy.ingest_roots
      },
      provider_route: route,
      routing: %{
        provider_name: provider_name(route.provider),
        fallback_names: Enum.map(route.fallbacks, &provider_name/1),
        source: route.source,
        budget: Map.get(route, :budget, %{}),
        workload: Map.get(route, :workload, %{})
      }
    }
  end

  def effective_provider_route(nil, process_type),
    do: effective_provider_route(nil, process_type, [])

  def effective_provider_route(agent_id, process_type),
    do: effective_provider_route(agent_id, process_type, [])

  def effective_provider_route(agent_id, process_type, opts) do
    base_route = Providers.effective_provider_route(agent_id, process_type, opts)
    workload = workload_routing_state(process_type)

    {selected_provider, selected_fallbacks, source, applied?} =
      maybe_promote_workload_fallback(base_route, workload)

    base_route
    |> Map.put(:provider, selected_provider)
    |> Map.put(:fallbacks, selected_fallbacks)
    |> Map.put(:source, source)
    |> Map.put(
      :workload,
      workload
      |> Map.put(:applied?, applied?)
      |> Map.put(:selected_provider_name, provider_name(selected_provider))
    )
  end

  def authorize_tool(agent_id, tool_name, channel, opts \\ []) do
    decision = tool_decision(agent_id, tool_name, channel, opts)

    if decision.allowed? do
      :ok
    else
      {:error, {:tool_disabled_by_policy, tool_name, channel}}
    end
  end

  def tool_decision(agent_id, tool_name, channel, opts \\ []) do
    policy = effective_policy(agent_id, opts).tool_policy
    spec = Map.get(@tool_specs, tool_name, %{enabled_field: nil, channels_field: nil})
    enabled? = if(spec.enabled_field, do: Map.get(policy, spec.enabled_field, false), else: true)
    channels = if(spec.channels_field, do: Map.get(policy, spec.channels_field, []), else: :all)

    channel_allowed? =
      case channels do
        :all -> true
        values -> channel in values
      end

    %{
      tool_name: tool_name,
      channel: channel,
      enabled?: enabled?,
      channel_allowed?: channel_allowed?,
      allowed?: enabled? and channel_allowed?,
      channels: channels
    }
  end

  def authorize_delivery(agent_id, mode, channel, opts \\ []) when mode in [:interactive, :job] do
    policy = effective_policy(agent_id, opts).control_policy

    allowed_channels =
      case mode do
        :interactive -> policy.interactive_delivery_channels
        :job -> policy.job_delivery_channels
      end

    if channel in allowed_channels do
      :ok
    else
      {:error, {:delivery_channel_blocked_by_policy, channel}}
    end
  end

  def authorize_ingest_path(agent_id, workspace_root, file_path, opts \\ []) do
    roots = effective_policy(agent_id, opts).control_policy.ingest_roots
    candidate = Path.expand(file_path)

    allowed? =
      Enum.any?(roots, fn root ->
        allowed_root = Path.expand(root, workspace_root)
        candidate == allowed_root or String.starts_with?(candidate, allowed_root <> "/")
      end)

    if allowed? do
      :ok
    else
      {:error, {:ingest_path_not_allowed, roots}}
    end
  end

  def recent_auth_required?(agent_id \\ nil, opts \\ []) do
    effective_policy(agent_id, opts).auth.recent_auth_required
  end

  defp tool_access(policy) do
    ~w(workspace_list workspace_read workspace_write http_fetch browser_automation web_search shell_command)
    |> Enum.map(fn tool_name ->
      decision = tool_decision_from_policy(policy, tool_name)

      %{
        tool_name: tool_name,
        enabled?: decision.enabled?,
        channels: decision.channels
      }
    end)
    |> Enum.sort_by(& &1.tool_name)
  end

  defp tool_decision_from_policy(policy, tool_name) do
    spec = Map.fetch!(@tool_specs, tool_name)
    enabled? = Map.get(policy, spec.enabled_field, false)
    channels = if(spec.channels_field, do: Map.get(policy, spec.channels_field, []), else: :all)

    %{
      tool_name: tool_name,
      enabled?: enabled?,
      channels: channels
    }
  end

  defp workload_routing_state(process_type) do
    scheduler = Jobs.scheduler_status()
    open_circuits = length(scheduler.open_circuits || [])
    timeout_runs = length(scheduler.timeout_runs || [])
    recent_failures = Enum.count(scheduler.runs || [], &(&1.status in ["error", "timeout"]))

    prefer_fallback? =
      process_type in @background_processes and
        (open_circuits > 0 or timeout_runs > 0 or recent_failures >= 3)

    reason =
      cond do
        open_circuits > 0 -> "open_circuit_jobs"
        timeout_runs > 0 -> "recent_timeout_runs"
        recent_failures >= 3 -> "recent_failures"
        true -> "steady"
      end

    %{
      process_type: process_type,
      pressure: if(prefer_fallback?, do: "high", else: "normal"),
      open_circuits: open_circuits,
      timeout_runs: timeout_runs,
      recent_failures: recent_failures,
      prefer_fallback?: prefer_fallback?,
      reason: reason
    }
  end

  defp maybe_promote_workload_fallback(route, workload) do
    budget_override? =
      route.source
      |> to_string()
      |> String.starts_with?("budget:")

    cond do
      budget_override? ->
        {route.provider, route.fallbacks, route.source, false}

      not workload.prefer_fallback? or route.fallbacks == [] ->
        {route.provider, route.fallbacks, route.source, false}

      true ->
        promoted = hd(route.fallbacks)
        remaining = Enum.reject([route.provider | tl(route.fallbacks)], &is_nil/1)
        {promoted, remaining, "workload:" <> workload.reason, true}
    end
  end

  defp provider_name(nil), do: "mock"
  defp provider_name(provider), do: provider.name || provider.model || provider.kind || "provider"
end
