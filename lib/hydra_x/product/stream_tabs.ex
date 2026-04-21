defmodule HydraX.Product.StreamTabs do
  @moduledoc """
  Three-tab Stream backend (spec §4–§6):

    * `:activity`   — reverse-chronological `stream_entries` history
    * `:needs_you`  — live items awaiting the user (proposing tasks, stale
                      waiting_for_input tasks, historical `needs_you` entries)
    * `:blockers`   — live stuck items (blocked >1h, failed <24h, stalled
                      waiting_for_input >24h, stalled flows, historical
                      `blockers` entries)

  Each helper returns a list of uniform `item()` maps so the frontend has
  one row shape to render regardless of whether the item is a live task or
  a persisted `StreamEntry`.
  """

  import Ecto.Query

  alias HydraX.Coherence.Contradiction
  alias HydraX.Repo
  alias HydraX.Product.AgentTask
  alias HydraX.Product.Flow
  alias HydraX.Product.StreamEntry

  @type item :: %{
          id: String.t(),
          tab: String.t(),
          kind: String.t(),
          title: String.t(),
          summary: String.t() | nil,
          actor_agent_id: String.t() | nil,
          age_seconds: integer(),
          source_task_id: integer() | nil,
          stream_entry_id: integer() | nil,
          flow_id: integer() | nil,
          context_type: String.t() | nil,
          context_id: integer() | nil,
          state: String.t() | nil,
          severity: integer(),
          inserted_at: DateTime.t()
        }

  # Spec §5 threshold: waiting_for_input ≥2h bubbles into Needs You.
  @needs_you_stale_hours 2

  # Spec §6 thresholds.
  @blocker_blocked_hours 1
  @blocker_waiting_hours 24
  @blocker_failed_recent_hours 24

  @limit_default 200

  ## Activity

  def list_activity(project_id, opts \\ []) do
    project_id = to_int(project_id)
    limit = Keyword.get(opts, :limit, @limit_default)

    group? = Keyword.get(opts, :group, true)

    StreamEntry
    |> where([e], e.project_id == ^project_id and e.tab == "activity")
    |> apply_agent_filter(opts[:agent_id])
    |> apply_search_filter(opts[:search])
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&stream_entry_item/1)
    |> maybe_burst_group(group?)
  end

  # Stream B3.2 — collapse same-agent entries within a 30-minute window
  # into a single grouped item (≥3 entries required).
  @burst_window_seconds 30 * 60
  @burst_min 3

  defp maybe_burst_group(items, false), do: items

  defp maybe_burst_group(items, true) do
    items
    |> Enum.chunk_while(
      [],
      fn item, acc ->
        case acc do
          [] ->
            {:cont, [item]}

          [head | _] ->
            if same_burst?(item, head) do
              {:cont, [item | acc]}
            else
              {:cont, Enum.reverse(acc), [item]}
            end
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.flat_map(&maybe_collapse_group/1)
  end

  defp same_burst?(a, b) do
    a.actor_agent_id != nil and
      a.actor_agent_id == b.actor_agent_id and
      a.kind == "stream_entry" and b.kind == "stream_entry" and
      abs_seconds_diff(a.inserted_at, b.inserted_at) <= @burst_window_seconds
  end

  defp abs_seconds_diff(a, b) when is_struct(a, DateTime) and is_struct(b, DateTime),
    do: abs(DateTime.diff(a, b))

  defp abs_seconds_diff(_, _), do: :infinity

  defp maybe_collapse_group(group) when length(group) < @burst_min, do: group

  defp maybe_collapse_group([first | _] = group) do
    count = length(group)
    agent = first.actor_agent_id || "agent"
    pretty = agent |> String.replace("_", " ") |> String.capitalize()
    oldest = List.last(group)

    [
      %{
        id: "burst:#{agent}:#{first.stream_entry_id || first.id}",
        tab: "activity",
        kind: "burst",
        title: "#{pretty} made #{count} changes",
        summary:
          group
          |> Enum.take(3)
          |> Enum.map(& &1.title)
          |> Enum.join(" · "),
        actor_agent_id: agent,
        age_seconds:
          (oldest.inserted_at && DateTime.diff(DateTime.utc_now(), oldest.inserted_at)) || 0,
        source_task_id: nil,
        stream_entry_id: nil,
        flow_id: nil,
        context_type: nil,
        context_id: nil,
        state: nil,
        severity: 1,
        inserted_at: first.inserted_at,
        group_items: group
      }
    ]
  end

  defp apply_agent_filter(query, nil), do: query
  defp apply_agent_filter(query, ""), do: query

  defp apply_agent_filter(query, agent_id) when is_binary(agent_id),
    do: where(query, [e], e.source_agent_id == ^agent_id)

  defp apply_search_filter(query, nil), do: query
  defp apply_search_filter(query, ""), do: query

  defp apply_search_filter(query, term) when is_binary(term) do
    like = "%#{term}%"
    where(query, [e], ilike(e.title, ^like) or ilike(e.summary, ^like))
  end

  ## Needs You

  def list_needs_you(project_id, opts \\ []) do
    project_id = to_int(project_id)
    limit = Keyword.get(opts, :limit, @limit_default)
    now = DateTime.utc_now()

    proposing = list_proposing_tasks(project_id)
    waiting = list_waiting_for_input_tasks(project_id, now, min_hours: @needs_you_stale_hours)
    historical = list_historical(project_id, "needs_you")

    merge_unique(proposing ++ waiting ++ historical)
    |> sort_needs_you()
    |> Enum.take(limit)
  end

  ## Blockers

  def list_blockers(project_id, opts \\ []) do
    project_id = to_int(project_id)
    limit = Keyword.get(opts, :limit, @limit_default)
    now = DateTime.utc_now()

    blocked = list_blocked_tasks(project_id, now)
    failed = list_failed_tasks(project_id, now)
    stuck_waiting = list_waiting_for_input_tasks(project_id, now, min_hours: @blocker_waiting_hours)
    stalled = list_stalled_flows(project_id)
    historical = list_historical(project_id, "blockers")
    contradictions = list_contradictions(project_id)

    merge_unique(
      blocked ++ failed ++ stuck_waiting ++ stalled ++ historical ++ contradictions
    )
    |> sort_by_severity_then_age()
    |> Enum.take(limit)
  end

  defp list_contradictions(project_id) do
    Contradiction
    |> where([c], c.project_id == ^project_id and c.status in ["open", "under_review"])
    |> where([c], c.severity in ["medium", "high"])
    |> order_by([c], desc: c.detected_at)
    |> limit(50)
    |> Repo.all()
    |> Enum.map(&contradiction_item/1)
  end

  defp contradiction_item(%Contradiction{} = c) do
    anchor = c.detected_at || c.inserted_at
    age = DateTime.diff(DateTime.utc_now(), anchor)

    severity_score =
      case c.severity do
        "high" -> 5
        "medium" -> 3
        _ -> 1
      end

    %{
      id: "contradiction:#{c.id}",
      tab: "blockers",
      kind: "contradiction",
      title: "Contradiction: #{c.node_a_type} ↔ #{c.node_b_type}",
      summary: c.explanation,
      actor_agent_id: "coherence",
      age_seconds: max(age, 0),
      source_task_id: nil,
      stream_entry_id: nil,
      flow_id: nil,
      context_type: "contradiction",
      context_id: c.id,
      state: c.status,
      severity: severity_score,
      inserted_at: anchor
    }
  end

  ## Counts

  @doc """
  Per-tab counts for the Stream tab badges. Activity is unbounded so
  returns `nil` (UI renders as "no badge").

  Uses direct count queries rather than listing + `length/1` so badge
  refresh stays O(matching rows) instead of fetching full row payloads.
  """
  def counts(project_id) do
    project_id = to_int(project_id)
    now = DateTime.utc_now()

    %{
      activity: nil,
      needs_you: count_needs_you(project_id, now),
      blockers: count_blockers(project_id, now)
    }
  end

  defp count_needs_you(project_id, now) do
    waiting_cutoff = DateTime.add(now, -@needs_you_stale_hours * 3600, :second)

    proposing =
      from(t in AgentTask,
        where:
          t.project_id == ^project_id and t.state == "proposing" and
            (is_nil(t.deferred_until) or t.deferred_until <= ^now)
      )
      |> Repo.aggregate(:count, :id)

    waiting =
      from(t in AgentTask,
        where:
          t.project_id == ^project_id and t.state == "waiting_for_input" and
            t.last_state_change_at <= ^waiting_cutoff and
            (is_nil(t.deferred_until) or t.deferred_until <= ^now)
      )
      |> Repo.aggregate(:count, :id)

    historical =
      from(e in StreamEntry,
        where:
          e.project_id == ^project_id and e.tab == "needs_you" and
            is_nil(e.actioned_at)
      )
      |> Repo.aggregate(:count, :id)

    proposing + waiting + historical
  end

  defp count_blockers(project_id, now) do
    blocked_cutoff = DateTime.add(now, -@blocker_blocked_hours * 3600, :second)
    failed_cutoff = DateTime.add(now, -@blocker_failed_recent_hours * 3600, :second)
    waiting_cutoff = DateTime.add(now, -@blocker_waiting_hours * 3600, :second)

    blocked =
      from(t in AgentTask,
        where:
          t.project_id == ^project_id and t.state == "blocked" and
            t.last_state_change_at <= ^blocked_cutoff and
            (is_nil(t.deferred_until) or t.deferred_until <= ^now)
      )
      |> Repo.aggregate(:count, :id)

    failed =
      from(t in AgentTask,
        where:
          t.project_id == ^project_id and t.state == "failed" and
            t.last_state_change_at >= ^failed_cutoff and
            (is_nil(t.deferred_until) or t.deferred_until <= ^now)
      )
      |> Repo.aggregate(:count, :id)

    waiting =
      from(t in AgentTask,
        where:
          t.project_id == ^project_id and t.state == "waiting_for_input" and
            t.last_state_change_at <= ^waiting_cutoff and
            (is_nil(t.deferred_until) or t.deferred_until <= ^now)
      )
      |> Repo.aggregate(:count, :id)

    stalled =
      from(f in Flow,
        where: f.project_id == ^project_id and f.status == "stalled"
      )
      |> Repo.aggregate(:count, :id)

    historical =
      from(e in StreamEntry,
        where:
          e.project_id == ^project_id and e.tab == "blockers" and
            is_nil(e.actioned_at)
      )
      |> Repo.aggregate(:count, :id)

    contradictions =
      from(c in Contradiction,
        where:
          c.project_id == ^project_id and c.status in ["open", "under_review"] and
            c.severity in ["medium", "high"]
      )
      |> Repo.aggregate(:count, :id)

    blocked + failed + waiting + stalled + historical + contradictions
  end

  ## Default tab resolution (spec §7)

  def default_tab(project_id) do
    project_id = to_int(project_id)
    needs = length(list_needs_you(project_id, limit: 1))

    cond do
      needs > 0 -> "needs_you"
      has_old_blockers?(project_id) -> "blockers"
      true -> "activity"
    end
  end

  defp has_old_blockers?(project_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)

    Repo.exists?(
      from t in AgentTask,
        where: t.project_id == ^project_id and t.state in ["blocked", "failed"] and t.last_state_change_at <= ^cutoff
    )
  end

  ## Live task queries

  defp list_proposing_tasks(project_id) do
    now = DateTime.utc_now()

    AgentTask
    |> where([t], t.project_id == ^project_id and t.state == "proposing")
    |> exclude_deferred(now)
    |> Repo.all()
    |> Enum.map(fn task -> task_item(task, "proposing") end)
  end

  defp list_waiting_for_input_tasks(project_id, now, opts) do
    min_hours = Keyword.fetch!(opts, :min_hours)
    cutoff = DateTime.add(now, -min_hours * 3600, :second)

    AgentTask
    |> where([t], t.project_id == ^project_id and t.state == "waiting_for_input" and t.last_state_change_at <= ^cutoff)
    |> exclude_deferred(now)
    |> Repo.all()
    |> Enum.map(fn task -> task_item(task, "waiting_for_input") end)
  end

  defp list_blocked_tasks(project_id, now) do
    cutoff = DateTime.add(now, -@blocker_blocked_hours * 3600, :second)

    AgentTask
    |> where([t], t.project_id == ^project_id and t.state == "blocked" and t.last_state_change_at <= ^cutoff)
    |> exclude_deferred(now)
    |> Repo.all()
    |> Enum.map(fn task -> task_item(task, "blocked") end)
  end

  defp list_failed_tasks(project_id, now) do
    cutoff = DateTime.add(now, -@blocker_failed_recent_hours * 3600, :second)

    AgentTask
    |> where(
      [t],
      t.project_id == ^project_id and t.state == "failed" and
        t.last_state_change_at >= ^cutoff
    )
    |> exclude_deferred(now)
    |> Repo.all()
    |> Enum.map(fn task -> task_item(task, "failed") end)
  end

  defp exclude_deferred(query, now) do
    where(query, [t], is_nil(t.deferred_until) or t.deferred_until <= ^now)
  end

  defp list_stalled_flows(project_id) do
    Flow
    |> where([f], f.project_id == ^project_id and f.status == "stalled")
    |> Repo.all()
    |> Enum.map(&flow_item/1)
  end

  defp list_historical(project_id, tab) do
    StreamEntry
    |> where(
      [e],
      e.project_id == ^project_id and e.tab == ^tab and is_nil(e.actioned_at)
    )
    |> order_by([e], desc: e.inserted_at)
    |> limit(50)
    |> Repo.all()
    |> Enum.map(&stream_entry_item/1)
  end

  ## Item builders

  defp stream_entry_item(%StreamEntry{} = e) do
    age = DateTime.diff(DateTime.utc_now(), e.inserted_at || DateTime.utc_now())

    %{
      id: "entry:#{e.id}",
      tab: e.tab,
      kind: "stream_entry",
      title: e.title,
      summary: e.summary,
      actor_agent_id: e.source_agent_id,
      age_seconds: max(age, 0),
      source_task_id: e.source_task_id,
      stream_entry_id: e.id,
      flow_id: nil,
      context_type: e.context_type,
      context_id: e.context_id,
      state: nil,
      severity: severity_for_entry(e),
      inserted_at: e.inserted_at
    }
  end

  defp task_item(%AgentTask{} = task, kind) do
    anchor = task.last_state_change_at || task.inserted_at
    age = DateTime.diff(DateTime.utc_now(), anchor)

    tab =
      case kind do
        "proposing" -> "needs_you"
        "waiting_for_input" -> if age >= @blocker_waiting_hours * 3600, do: "blockers", else: "needs_you"
        "blocked" -> "blockers"
        "failed" -> "blockers"
      end

    %{
      id: "task:#{task.id}",
      tab: tab,
      kind: kind,
      title: task.title,
      summary: task.state_reason || task.description,
      actor_agent_id: task.agent_id,
      age_seconds: max(age, 0),
      source_task_id: task.id,
      stream_entry_id: nil,
      flow_id: task.flow_id,
      context_type: task.context_type,
      context_id: task.context_id,
      state: task.state,
      severity: severity_for_task(kind, age),
      inserted_at: anchor
    }
  end

  defp flow_item(%Flow{} = flow) do
    anchor = flow.updated_at || flow.inserted_at
    age = DateTime.diff(DateTime.utc_now(), anchor)

    %{
      id: "flow:#{flow.id}",
      tab: "blockers",
      kind: "stalled_flow",
      title: flow.name,
      summary: "Flow stalled across #{Enum.join(flow.participating_agent_ids, " → ")}",
      actor_agent_id: nil,
      age_seconds: max(age, 0),
      source_task_id: flow.originating_task_id,
      stream_entry_id: nil,
      flow_id: flow.id,
      context_type: "flow",
      context_id: flow.id,
      state: flow.status,
      severity: 2,
      inserted_at: anchor
    }
  end

  ## Severity + ordering

  # Higher severity sorts first.
  defp severity_for_task("failed", _), do: 5
  defp severity_for_task("blocked", _), do: 4
  defp severity_for_task("proposing", _), do: 3
  defp severity_for_task("waiting_for_input", age) when age >= 24 * 3600, do: 4
  defp severity_for_task("waiting_for_input", _), do: 2
  defp severity_for_task(_, _), do: 1

  defp severity_for_entry(%StreamEntry{tab: "blockers"}), do: 4
  defp severity_for_entry(%StreamEntry{tab: "needs_you"}), do: 3
  defp severity_for_entry(_), do: 1

  defp sort_needs_you(items) do
    # Spec §5: oldest first so stale requests bubble up; but contradictions
    # and blocker-candidates outrank age.
    Enum.sort_by(items, fn i -> {-i.severity, -i.age_seconds} end)
  end

  defp sort_by_severity_then_age(items) do
    # Higher severity first, then oldest first within a tier.
    Enum.sort_by(items, fn i -> {-i.severity, -i.age_seconds} end)
  end

  ## Merge-dedupe — a task could show up in both live query and historical.
  ## Prefer the live-task entry (more current) over the historical entry.

  defp merge_unique(items) do
    items
    |> Enum.group_by(fn i ->
      cond do
        i.source_task_id -> {:task, i.source_task_id}
        i.flow_id -> {:flow, i.flow_id}
        i.stream_entry_id -> {:entry, i.stream_entry_id}
        true -> make_ref()
      end
    end)
    |> Enum.map(fn {_k, group} -> Enum.max_by(group, & &1.severity) end)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
