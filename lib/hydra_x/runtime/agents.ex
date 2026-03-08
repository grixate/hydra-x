defmodule HydraX.Runtime.Agents do
  @moduledoc """
  Agent CRUD, runtime state management, bulletin generation, and workspace operations.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Memory
  alias HydraX.Repo
  alias HydraX.Workspace

  alias HydraX.Runtime.{AgentProfile, Helpers}

  @default_agent_slug "hydra-primary"

  def list_agents do
    AgentProfile
    |> order_by([agent], desc: agent.is_default, asc: agent.name)
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(AgentProfile, id)

  def get_agent_by_slug(slug) do
    Repo.get_by(AgentProfile, slug: slug)
  end

  def get_default_agent do
    Repo.one(from(agent in AgentProfile, where: agent.is_default == true, limit: 1))
  end

  def ensure_default_agent! do
    case get_default_agent() || get_agent_by_slug(@default_agent_slug) do
      nil ->
        attrs = %{
          name: "Hydra Prime",
          slug: @default_agent_slug,
          status: "active",
          description: "Default Hydra-X operator agent",
          is_default: true,
          workspace_root: Config.default_workspace(@default_agent_slug)
        }

        case save_agent(attrs) do
          {:ok, agent} ->
            Workspace.Scaffold.copy_template!(agent.workspace_root)
            agent

          {:error, _changeset} ->
            get_agent_by_slug(@default_agent_slug)
        end

      agent ->
        Workspace.Scaffold.copy_template!(agent.workspace_root)
        agent
    end
  end

  def change_agent(agent \\ %AgentProfile{}, attrs \\ %{}) do
    AgentProfile.changeset(agent, attrs)
  end

  def save_agent(attrs) when is_map(attrs) do
    save_agent(%AgentProfile{}, attrs)
  end

  def save_agent(%AgentProfile{} = agent, attrs) do
    Repo.transaction(fn ->
      attrs = normalize_agent_attrs(attrs)
      changeset = AgentProfile.changeset(agent, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.is_default do
        from(other in AgentProfile, where: other.id != ^record.id and other.is_default == true)
        |> Repo.update_all(set: [is_default: false])
      end

      Workspace.Scaffold.copy_template!(record.workspace_root)
      record
    end)
    |> Helpers.unwrap_transaction()
  end

  def update_agent_runtime_state(%AgentProfile{} = agent, attrs) when is_map(attrs) do
    current = agent.runtime_state || %{}
    save_agent(agent, %{runtime_state: Map.merge(current, attrs)})
  end

  def toggle_agent_status!(id) do
    agent = get_agent!(id)
    next = if agent.status == "active", do: "paused", else: "active"
    {:ok, updated} = save_agent(agent, %{status: next})

    case updated.status do
      "active" -> start_agent_runtime!(updated.id)
      _ -> stop_agent_runtime!(updated.id)
    end

    updated
  end

  def set_default_agent!(id) do
    agent = get_agent!(id)
    {:ok, updated} = save_agent(agent, %{is_default: true})
    updated
  end

  def repair_agent_workspace!(id) do
    agent = get_agent!(id)
    Workspace.Scaffold.copy_template!(agent.workspace_root)
    agent
  end

  def agent_bulletin(id) when is_integer(id) do
    agent = get_agent!(id)
    bulletin = get_in(agent.runtime_state, ["bulletin"])

    %{
      agent: agent,
      content: bulletin,
      updated_at: get_in(agent.runtime_state, ["bulletin_updated_at"]),
      memory_count:
        Memory.list_memories(agent_id: agent.id, limit: 6, status: "active") |> length()
    }
  end

  def compaction_policy(id) when is_integer(id) do
    agent = get_agent!(id)
    persisted = get_in(agent.runtime_state || %{}, ["compaction_policy"]) || %{}
    defaults = Config.compaction_thresholds()

    %{
      soft: map_integer(persisted["soft"], defaults.soft),
      medium: map_integer(persisted["medium"], defaults.medium),
      hard: map_integer(persisted["hard"], defaults.hard)
    }
  end

  def save_compaction_policy!(id, attrs) when is_integer(id) and is_map(attrs) do
    agent = get_agent!(id)
    policy = normalize_compaction_policy(attrs)
    validate_compaction_policy!(policy)

    {:ok, updated} =
      update_agent_runtime_state(agent, %{
        "compaction_policy" => %{
          "soft" => policy.soft,
          "medium" => policy.medium,
          "hard" => policy.hard
        }
      })

    Helpers.audit_operator_action("Updated compaction policy for #{updated.slug}",
      agent: updated,
      metadata: %{
        "soft" => policy.soft,
        "medium" => policy.medium,
        "hard" => policy.hard
      }
    )

    policy
  end

  def refresh_agent_bulletin!(id) when is_integer(id) do
    agent = get_agent!(id)
    bulletin = render_agent_bulletin(agent.id)
    updated_at = DateTime.utc_now()

    {:ok, updated_agent} =
      update_agent_runtime_state(agent, %{
        "bulletin" => bulletin,
        "bulletin_updated_at" => updated_at
      })

    Helpers.audit_operator_action(
      "Refreshed bulletin for #{updated_agent.slug}",
      agent: updated_agent,
      metadata: %{
        "memory_count" => Memory.list_memories(agent_id: agent.id, limit: 6) |> length()
      }
    )

    %{
      agent: updated_agent,
      content: bulletin,
      updated_at: updated_at,
      memory_count:
        Memory.list_memories(agent_id: agent.id, limit: 6, status: "active") |> length()
    }
  end

  def agent_runtime_status(%AgentProfile{} = agent) do
    pid = HydraX.Agent.pid(agent.id)
    warmup = HydraX.Runtime.Providers.effective_provider_route(agent.id, "channel").warmup

    %{
      running: not is_nil(pid),
      pid: pid && inspect(pid),
      last_started_at: agent.last_started_at,
      persisted_status: agent.status,
      readiness: readiness_status(not is_nil(pid), warmup["status"]),
      warmup_status: warmup["status"],
      warmed_at: warmup["warmed_at"],
      last_warm_error: warmup["last_error"],
      selected_provider_id: warmup["selected_provider_id"]
    }
  end

  def agent_runtime_status(id), do: get_agent!(id) |> agent_runtime_status()

  def start_agent_runtime!(id) do
    agent = get_agent!(id)
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, updated} =
      save_agent(agent, %{
        last_started_at: DateTime.utc_now(),
        runtime_state: Map.merge(agent.runtime_state || %{}, %{"running" => true})
      })

    _ = HydraX.Runtime.Providers.warm_agent_provider_routing(updated.id)
    updated
  end

  def stop_agent_runtime!(id) do
    agent = get_agent!(id)
    :ok = HydraX.Agent.ensure_stopped(agent)

    {:ok, updated} =
      save_agent(agent, %{
        runtime_state:
          Map.merge(agent.runtime_state || %{}, %{
            "running" => false,
            "last_stopped_at" => DateTime.utc_now()
          })
      })

    updated
  end

  def restart_agent_runtime!(id) do
    agent = get_agent!(id)
    :ok = HydraX.Agent.ensure_stopped(agent)
    start_agent_runtime!(agent.id)
  end

  def reconcile_agents! do
    ensure_default_agent!()

    list_agents()
    |> Enum.reduce(%{started: 0, stopped: 0}, fn agent, acc ->
      case {agent.status, HydraX.Agent.running?(agent)} do
        {"active", false} ->
          start_agent_runtime!(agent.id)
          %{acc | started: acc.started + 1}

        {"active", true} ->
          acc

        {_, true} ->
          stop_agent_runtime!(agent.id)
          %{acc | stopped: acc.stopped + 1}

        _ ->
          acc
      end
    end)
  end

  # -- Private helpers --

  defp render_agent_bulletin(agent_id) do
    active = Memory.list_memories(agent_id: agent_id, limit: 50, status: "active")

    conflict_count =
      Memory.list_memories(agent_id: agent_id, limit: 50, status: "conflicted") |> length()

    # Ensure type diversity: pick the top memory from each type first
    by_type = Enum.group_by(active, & &1.type)

    diverse =
      by_type
      |> Enum.map(fn {_type, entries} -> List.first(entries) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&recency_score/1, :desc)
      |> Enum.take(8)

    # Fill remaining slots with highest-importance recent memories not yet included
    diverse_ids = MapSet.new(diverse, & &1.id)
    remaining_slots = max(10 - length(diverse), 0)

    filler =
      active
      |> Enum.reject(&MapSet.member?(diverse_ids, &1.id))
      |> Enum.sort_by(&recency_score/1, :desc)
      |> Enum.take(remaining_slots)

    selected = diverse ++ filler

    lines =
      Enum.map(selected, fn memory ->
        "- [#{memory.type}] #{memory.content}"
      end)

    conflict_warning =
      if conflict_count > 0 do
        ["- [WARNING] #{conflict_count} conflicted memories need operator review"]
      else
        []
      end

    Enum.join(lines ++ conflict_warning, "\n")
  end

  defp recency_score(memory) do
    seen = memory.last_seen_at || memory.updated_at || memory.inserted_at
    importance = memory.importance || 0.5

    # Decay: memories seen within the last day score highest
    seconds_ago = DateTime.diff(DateTime.utc_now(), seen, :second)
    decay = 1.0 / (1.0 + seconds_ago / 86_400)

    importance * 0.6 + decay * 0.4
  end

  defp normalize_agent_attrs(attrs) do
    normalized = Helpers.normalize_string_keys(attrs)

    cond do
      Map.has_key?(normalized, "workspace_root") ->
        normalized

      is_binary(normalized["slug"]) and normalized["slug"] != "" ->
        Map.put(normalized, "workspace_root", Config.default_workspace(normalized["slug"]))

      true ->
        normalized
    end
  end

  defp normalize_compaction_policy(attrs) do
    defaults = Config.compaction_thresholds()
    normalized = Helpers.normalize_string_keys(attrs)

    %{
      soft: map_integer(normalized["soft"], defaults.soft),
      medium: map_integer(normalized["medium"], defaults.medium),
      hard: map_integer(normalized["hard"], defaults.hard)
    }
  end

  defp validate_compaction_policy!(%{soft: soft, medium: medium, hard: hard}) do
    cond do
      soft < 1 or medium < 1 or hard < 1 ->
        raise ArgumentError, "compaction thresholds must be positive integers"

      not (soft < medium and medium < hard) ->
        raise ArgumentError, "compaction thresholds must satisfy soft < medium < hard"

      true ->
        :ok
    end
  end

  defp map_integer(nil, default), do: default
  defp map_integer("", default), do: default
  defp map_integer(value, _default) when is_integer(value), do: value
  defp map_integer(value, _default) when is_binary(value), do: String.to_integer(value)

  defp readiness_status(false, _warmup_status), do: "cold"
  defp readiness_status(true, "ready"), do: "ready"
  defp readiness_status(true, "mock"), do: "mock"
  defp readiness_status(true, _), do: "degraded"
end
