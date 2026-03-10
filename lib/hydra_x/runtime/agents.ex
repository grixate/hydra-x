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
    retry_busy_transaction(fn ->
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
    end)
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

    prioritized =
      prioritize_bulletin_memories(active)

    sections =
      []
      |> maybe_add_section(
        conflict_count > 0,
        "Warnings",
        ["- #{conflict_count} conflicted memories need operator review"]
      )
      |> maybe_add_section(
        prioritized.goals != [],
        "Active Goals And Todos",
        Enum.map(prioritized.goals, &bulletin_line/1)
      )
      |> maybe_add_section(
        prioritized.decisions != [],
        "Current Decisions And Preferences",
        Enum.map(prioritized.decisions, &bulletin_line/1)
      )
      |> maybe_add_section(
        prioritized.channels != [],
        "Channel-Specific Context",
        Enum.map(prioritized.channels, &bulletin_line/1)
      )
      |> maybe_add_section(
        prioritized.context != [],
        "Relevant Context",
        Enum.map(prioritized.context, &bulletin_line/1)
      )

    case sections do
      [] -> "No active memory yet."
      _ -> Enum.join(sections, "\n\n")
    end
  end

  defp prioritize_bulletin_memories(active) do
    ranked = Enum.sort_by(active, &bulletin_priority/1, :desc)

    goals =
      ranked
      |> Enum.filter(&(&1.type in ["Goal", "Todo"]))
      |> Enum.take(4)

    goal_ids = MapSet.new(goals, & &1.id)

    decisions =
      ranked
      |> Enum.reject(&MapSet.member?(goal_ids, &1.id))
      |> Enum.filter(&(&1.type in ["Decision", "Preference", "Identity"]))
      |> Enum.take(3)

    taken_ids = MapSet.union(goal_ids, MapSet.new(decisions, & &1.id))

    channels =
      ranked
      |> Enum.reject(&MapSet.member?(taken_ids, &1.id))
      |> Enum.filter(&(bulletin_channel(&1) && &1.type in ["Event", "Observation", "Fact"]))
      |> Enum.uniq_by(&bulletin_channel/1)
      |> Enum.take(3)

    taken_ids = MapSet.union(taken_ids, MapSet.new(channels, & &1.id))

    context =
      ranked
      |> Enum.reject(&MapSet.member?(taken_ids, &1.id))
      |> Enum.take(4)

    %{goals: goals, decisions: decisions, channels: channels, context: context}
  end

  defp bulletin_priority(memory) do
    type_weight =
      case memory.type do
        "Goal" -> 2.4
        "Todo" -> 2.2
        "Decision" -> 2.0
        "Preference" -> 1.8
        "Identity" -> 1.5
        "Event" -> 1.35
        "Observation" -> 1.25
        _ -> 1.0
      end

    type_weight + recency_score(memory) + channel_bulletin_boost(memory)
  end

  defp bulletin_line(memory) do
    prefix =
      case bulletin_channel(memory) do
        nil -> "[#{memory.type}]"
        channel -> "[#{memory.type}/#{channel}]"
      end

    "- #{prefix} #{memory.content}"
  end

  defp maybe_add_section(sections, false, _title, _lines), do: sections

  defp maybe_add_section(sections, true, title, lines) do
    sections ++ ["## #{title}\n" <> Enum.join(lines, "\n")]
  end

  defp recency_score(memory) do
    seen = memory.last_seen_at || memory.updated_at || memory.inserted_at
    importance = memory.importance || 0.5

    # Decay: memories seen within the last day score highest
    seconds_ago = DateTime.diff(DateTime.utc_now(), seen, :second)
    decay = 1.0 / (1.0 + seconds_ago / 86_400)

    importance * 0.6 + decay * 0.4
  end

  defp channel_bulletin_boost(memory) do
    if bulletin_channel(memory), do: 0.12, else: 0.0
  end

  defp bulletin_channel(memory) do
    get_in(memory.metadata || %{}, ["source_channel"]) ||
      (memory.conversation && memory.conversation.channel)
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

  defp retry_busy_transaction(fun, attempts \\ 3)

  defp retry_busy_transaction(fun, attempts) when attempts > 1 do
    fun.()
  rescue
    error in Exqlite.Error ->
      if String.contains?(Exception.message(error), "Database busy") do
        Process.sleep(40)
        retry_busy_transaction(fun, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp retry_busy_transaction(fun, _attempts), do: fun.()
end
