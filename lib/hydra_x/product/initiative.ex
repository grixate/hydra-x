defmodule HydraX.Product.Initiative do
  @moduledoc """
  Evaluates what autonomous work each agent should do based on
  the current graph state, recent events, and agent responsibilities.

  One GenServer per project. Subscribes to project PubSub events and
  runs periodic evaluations on a timer tick.
  """

  use GenServer

  import Ecto.Query

  alias HydraX.Product
  alias HydraX.Product.{AgentBridge, Graph, Coherence}
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Repo

  require Logger

  @tick_interval :timer.minutes(15)
  @agent_cooldown_seconds 300
  @max_items_per_tick 3
  @max_queue_size 50
  # Numeric priorities — fixes the atom sort bug from the spec
  # (atoms sort alphabetically: :high < :low < :medium which is wrong)
  @priority_values %{high: 3, medium: 2, low: 1}

  # --- Responsibility definitions per agent ---

  @researcher_checks [
    :check_watch_targets,
    :check_unprocessed_sources,
    :check_thin_evidence_areas,
    :check_insight_confidence_decay
  ]

  @strategist_checks [
    :check_undecided_insights,
    :check_decision_review_due,
    :check_strategy_memo_due,
    :check_simulation_opportunity
  ]

  @architect_checks [
    :check_unspecified_requirements,
    :check_dependency_audit_due,
    :check_technical_debt_signals
  ]

  @designer_checks [
    :check_undesigned_requirements,
    :check_design_consistency,
    :check_design_language_drift
  ]

  @coherence_checks [
    :check_full_scan_due,
    :check_unresolved_contradictions
  ]

  # --- GenServer ---

  def start_link(project_id) do
    GenServer.start_link(__MODULE__, project_id, name: via(project_id))
  end

  @impl true
  def init(project_id) do
    ProductPubSub.subscribe_project(project_id)
    schedule_tick()

    {:ok, %{
      project_id: project_id,
      last_actions: %{},
      queued_work: [],
      paused: false
    }}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      try do
        state
        |> evaluate_all()
        |> execute_batch()
      rescue
        error ->
          Logger.error("[Initiative] Tick failed for project #{state.project_id}: #{inspect(error)}")
          state
      end

    schedule_tick()
    {:noreply, state}
  end

  # React to graph events — uses the actual PubSub message format
  # (not the spec's incorrect {:product_event, ...} format)
  @impl true
  def handle_info({:product_project_event, "source.created", _payload}, state) do
    state = queue_work(state, "researcher", :analyze_new_source,
      "A new source has been uploaded. Analyze it and extract key insights with source references.",
      :high)
    {:noreply, state}
  end

  def handle_info({:product_project_event, "insight.created", _payload}, state) do
    state = queue_work(state, "strategist", :evaluate_new_insight,
      "A new insight has been created. Evaluate whether it warrants product decisions or updates to existing strategies.",
      :medium)
    {:noreply, state}
  end

  def handle_info({:product_project_event, "decision.created", _payload}, state) do
    state = queue_work(state, "architect", :assess_decision_feasibility,
      "A new decision has been recorded. Assess its technical feasibility and identify any architecture implications.",
      :medium)
    {:noreply, state}
  end

  def handle_info({:product_project_event, "simulation.completed", payload}, state) do
    # When a simulation completes, queue the proposing agent to analyze results
    sim_node_id = payload[:sim_node_id] || payload["sim_node_id"]
    title = payload[:title] || payload["title"] || "simulation"

    # Determine who proposed it so they can analyze
    proposed_by =
      try do
        id =
          cond do
            is_integer(sim_node_id) -> sim_node_id
            is_binary(sim_node_id) -> String.to_integer(sim_node_id)
            true -> nil
          end

        if id do
          sim = HydraX.Product.SimulationBridge.get_product_simulation!(id)
          Map.get(sim.metadata || %{}, "proposed_by") || "strategist"
        else
          "strategist"
        end
      rescue
        _ -> "strategist"
      end

    state = queue_work(state, proposed_by, :analyze_simulation_results,
      "Simulation '#{title}' (ID #{sim_node_id}) has completed. " <>
      "Review the simulation results in the simulation node metadata. " <>
      "Analyze the outcomes, identify key findings, and create a recommendation. " <>
      "If the results are conclusive, propose a decision or update an existing one. " <>
      "Update the relevant strategy memo artifact with your analysis.",
      :high)
    {:noreply, state}
  end

  def handle_info({:product_project_event, "artifact.updated", payload}, state) do
    # When an artifact is updated by an agent, the memory_agent should update the project summary
    updated_by = payload[:updated_by] || payload["updated_by"]
    artifact = payload[:artifact] || payload["artifact"]

    if updated_by != "memory_agent" && artifact do
      artifact_title = if is_map(artifact), do: Map.get(artifact, :title, "artifact"), else: "artifact"

      state = queue_work(state, "memory_agent", :update_project_summary,
        "The #{updated_by || "an agent"} updated artifact '#{artifact_title}'. " <>
        "Review whether the Project Summary artifact needs updating to reflect this change.",
        :low)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Catch-all for other project events
  def handle_info({:product_project_event, _event, _payload}, state) do
    {:noreply, state}
  end

  # Ignore other messages (e.g. source events, board events)
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Public API ---

  def pause(project_id), do: GenServer.cast(via(project_id), :pause)
  def resume(project_id), do: GenServer.cast(via(project_id), :resume)
  def status(project_id), do: GenServer.call(via(project_id), :status)

  @impl true
  def handle_cast(:pause, state), do: {:noreply, %{state | paused: true}}
  def handle_cast(:resume, state), do: {:noreply, %{state | paused: false}}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{
      project_id: state.project_id,
      paused: state.paused,
      queued_work_count: length(state.queued_work),
      last_actions: state.last_actions
    }, state}
  end

  # --- Evaluation logic ---

  defp evaluate_all(state) do
    project_id = state.project_id

    # Check trust level — cautious means no initiative
    project = Product.get_project!(project_id)

    if project.trust_level == "cautious" || over_budget?(project_id) do
      %{state | paused: true}
    else
      work_items =
        evaluate_agent(project_id, "researcher", @researcher_checks) ++
        evaluate_agent(project_id, "strategist", @strategist_checks) ++
        evaluate_agent(project_id, "architect", @architect_checks) ++
        evaluate_agent(project_id, "designer", @designer_checks) ++
        evaluate_agent(project_id, "coherence", @coherence_checks)

      # Deduplicate: merge new items with existing queue, keyed by {agent, check}
      new_queue =
        (state.queued_work ++ work_items)
        |> Enum.uniq_by(&{&1.agent, &1.check})

      # Cap queue size to prevent unbounded growth
      capped_queue = Enum.take(new_queue, @max_queue_size)
      %{state | queued_work: capped_queue, paused: false}
    end
  end

  defp evaluate_agent(project_id, agent, checks) do
    Enum.flat_map(checks, fn check ->
      case run_check(project_id, agent, check) do
        {:work_needed, prompt, priority} ->
          [%{agent: agent, check: check, prompt: prompt, priority: priority}]
        :ok ->
          []
      end
    end)
  end

  # --- Individual check implementations ---

  defp run_check(project_id, "researcher", :check_thin_evidence_areas) do
    density = Graph.density_report(project_id)
    thin_areas = Enum.filter(density, fn {_type, stats} -> stats.count > 0 && stats.avg_outgoing < 0.5 end)

    if length(thin_areas) > 0 do
      types = Enum.map(thin_areas, fn {type, _} -> type end) |> Enum.join(", ")
      {:work_needed,
       "The following areas of the product graph have thin evidence: #{types}. " <>
       "Search for additional research, data, or signals that could strengthen these areas. " <>
       "Create new insights with source references.",
       :medium}
    else
      :ok
    end
  end

  defp run_check(project_id, "researcher", :check_insight_confidence_decay) do
    stale_insights = Graph.stale_nodes(project_id, days: 60, node_types: ["insight"])

    if length(stale_insights) > 3 do
      titles = stale_insights |> Enum.take(5) |> Enum.map(& &1.title) |> Enum.join("; ")
      {:work_needed,
       "#{length(stale_insights)} insights haven't been revalidated in 60+ days, including: #{titles}. " <>
       "Review each insight against current information. Flag any that are no longer accurate. " <>
       "Update confidence levels.",
       :low}
    else
      :ok
    end
  end

  defp run_check(project_id, "strategist", :check_undecided_insights) do
    orphan_insights = find_insights_without_decisions(project_id)

    if length(orphan_insights) > 2 do
      titles = orphan_insights |> Enum.take(3) |> Enum.map(& &1.title) |> Enum.join("; ")
      {:work_needed,
       "#{length(orphan_insights)} insights exist without downstream decisions, including: #{titles}. " <>
       "Evaluate whether these insights warrant product decisions. If they do, draft decision proposals. " <>
       "If they're informational only, note why no decision is needed.",
       :medium}
    else
      :ok
    end
  end

  defp run_check(project_id, "strategist", :check_simulation_opportunity) do
    flags = Graph.open_flags(project_id, flag_type: "contradicted")
    decision_flags = Enum.filter(flags, &(&1.node_type == "decision"))

    if length(decision_flags) > 0 do
      {:work_needed,
       "#{length(decision_flags)} decisions have contradiction flags. " <>
       "Consider whether a simulation would help resolve the uncertainty. " <>
       "If so, propose a simulation configuration specifying what to test and why.",
       :high}
    else
      :ok
    end
  end

  defp run_check(project_id, "coherence", :check_full_scan_due) do
    last_scan = last_coherence_scan_time(project_id)
    hours_since = if last_scan, do: DateTime.diff(DateTime.utc_now(), last_scan, :hour), else: 999

    if hours_since > 24 do
      {:work_needed, :full_scan, :low}
    else
      :ok
    end
  end

  defp run_check(project_id, "coherence", :check_unresolved_contradictions) do
    flags = Graph.open_flags(project_id, flag_type: "contradicted")

    if length(flags) > 2 do
      {:work_needed,
       "#{length(flags)} contradiction flags are unresolved. " <>
       "Review each contradiction and propose resolutions.",
       :medium}
    else
      :ok
    end
  end

  # --- Researcher: watch targets ---

  defp run_check(project_id, "researcher", :check_watch_targets) do
    targets =
      HydraX.Product.WatchTarget
      |> where([w], w.project_id == ^project_id and w.status == "active")
      |> Repo.all()

    overdue =
      Enum.filter(targets, fn target ->
        case target.last_checked_at do
          nil -> true
          last -> DateTime.diff(DateTime.utc_now(), last, :hour) >= target.check_interval_hours
        end
      end)

    if length(overdue) > 0 do
      values = overdue |> Enum.take(3) |> Enum.map(& &1.value) |> Enum.join(", ")
      {:work_needed,
       "#{length(overdue)} watch targets are overdue for checking, including: #{values}. " <>
       "Review each target for new developments and create insights from any findings.",
       :medium}
    else
      :ok
    end
  end

  defp run_check(project_id, "researcher", :check_unprocessed_sources) do
    unprocessed =
      HydraX.Product.Source
      |> where([s], s.project_id == ^project_id and s.processing_status in ["pending", "uploaded"])
      |> Repo.aggregate(:count)

    if unprocessed > 0 do
      {:work_needed,
       "#{unprocessed} source(s) have been uploaded but not yet analyzed. " <>
       "Process each source, extract key findings, and create insights with citations.",
       :high}
    else
      :ok
    end
  end

  # --- Strategist: decision review and strategy memos ---

  defp run_check(project_id, "strategist", :check_decision_review_due) do
    cutoff = DateTime.utc_now() |> DateTime.add(-30 * 86400)

    stale_decisions =
      HydraX.Product.Decision
      |> where([d], d.project_id == ^project_id and d.status == "accepted" and d.updated_at < ^cutoff)
      |> Repo.aggregate(:count)

    if stale_decisions > 2 do
      {:work_needed,
       "#{stale_decisions} accepted decisions haven't been reviewed in 30+ days. " <>
       "Evaluate whether each decision still holds given current insights and market conditions. " <>
       "Flag any that need revision.",
       :low}
    else
      :ok
    end
  end

  defp run_check(project_id, "strategist", :check_strategy_memo_due) do
    # Check if a strategy_memo artifact exists and when it was last updated
    last_memo_update =
      HydraX.Product.Artifact
      |> where([a], a.project_id == ^project_id and a.artifact_type == "strategy_memo" and a.status == "active")
      |> order_by([a], desc: a.updated_at)
      |> limit(1)
      |> select([a], a.updated_at)
      |> Repo.one()

    days_since =
      case last_memo_update do
        nil -> 999
        ts -> DateTime.diff(DateTime.utc_now(), ts, :second) |> div(86400)
      end

    if days_since > 7 do
      {:work_needed,
       "It has been #{days_since} days since the last strategy memo update. " <>
       "Review the current state of decisions, insights, and simulations. " <>
       "Draft or update the strategy memo artifact with current recommendations.",
       :medium}
    else
      :ok
    end
  end

  # --- Architect ---

  defp run_check(project_id, "architect", :check_unspecified_requirements) do
    # Requirements that have no architecture node edges
    req_ids_with_arch =
      HydraX.Product.GraphEdge
      |> where([e],
        e.project_id == ^project_id and
        e.from_node_type == "requirement" and
        e.to_node_type == "architecture_node"
      )
      |> select([e], e.from_node_id)
      |> Repo.all()
      |> MapSet.new()

    unspecified =
      HydraX.Product.Requirement
      |> where([r], r.project_id == ^project_id and r.status in ["accepted", "draft"])
      |> Repo.all()
      |> Enum.reject(fn r -> MapSet.member?(req_ids_with_arch, r.id) end)

    if length(unspecified) > 1 do
      titles = unspecified |> Enum.take(3) |> Enum.map(& &1.title) |> Enum.join("; ")
      {:work_needed,
       "#{length(unspecified)} requirements have no architecture specification, including: #{titles}. " <>
       "Create architecture nodes that describe how each requirement will be implemented.",
       :medium}
    else
      :ok
    end
  end

  defp run_check(project_id, "architect", :check_dependency_audit_due) do
    # Check architecture nodes updated in last 7 days
    cutoff = DateTime.utc_now() |> DateTime.add(-7 * 86400)

    recent_arch =
      HydraX.Product.ArchitectureNode
      |> where([a], a.project_id == ^project_id and a.updated_at > ^cutoff)
      |> Repo.aggregate(:count)

    total_arch =
      HydraX.Product.ArchitectureNode
      |> where([a], a.project_id == ^project_id)
      |> Repo.aggregate(:count)

    if total_arch > 0 && recent_arch == 0 do
      {:work_needed,
       "No architecture nodes have been updated in 7+ days (#{total_arch} total). " <>
       "Audit dependencies and technical assumptions. Flag any that need updating.",
       :low}
    else
      :ok
    end
  end

  defp run_check(project_id, "architect", :check_technical_debt_signals) do
    flags = Graph.open_flags(project_id, node_type: "architecture_node")

    if length(flags) > 1 do
      {:work_needed,
       "#{length(flags)} architecture nodes have open flags. " <>
       "Review flagged nodes for technical debt or contradictions and propose resolutions.",
       :medium}
    else
      :ok
    end
  end

  # --- Designer ---

  defp run_check(project_id, "designer", :check_undesigned_requirements) do
    req_ids_with_design =
      HydraX.Product.GraphEdge
      |> where([e],
        e.project_id == ^project_id and
        e.from_node_type == "requirement" and
        e.to_node_type == "design_node"
      )
      |> select([e], e.from_node_id)
      |> Repo.all()
      |> MapSet.new()

    undesigned =
      HydraX.Product.Requirement
      |> where([r], r.project_id == ^project_id and r.status in ["accepted", "draft"])
      |> Repo.all()
      |> Enum.reject(fn r -> MapSet.member?(req_ids_with_design, r.id) end)

    if length(undesigned) > 1 do
      titles = undesigned |> Enum.take(3) |> Enum.map(& &1.title) |> Enum.join("; ")
      {:work_needed,
       "#{length(undesigned)} requirements have no design nodes, including: #{titles}. " <>
       "Create design specifications for each unaddressed requirement.",
       :medium}
    else
      :ok
    end
  end

  defp run_check(project_id, "designer", :check_design_consistency) do
    flags = Graph.open_flags(project_id, node_type: "design_node")

    if length(flags) > 1 do
      {:work_needed,
       "#{length(flags)} design nodes have open flags indicating potential inconsistencies. " <>
       "Review and resolve design contradictions.",
       :medium}
    else
      :ok
    end
  end

  defp run_check(project_id, "designer", :check_design_language_drift) do
    # Check if there's a design_language knowledge entry or artifact
    has_design_language =
      HydraX.Product.KnowledgeEntry
      |> where([k], k.project_id == ^project_id and k.entry_type == "design_language" and k.status == "active")
      |> Repo.exists?()

    has_design_language_artifact =
      HydraX.Product.Artifact
      |> where([a], a.project_id == ^project_id and a.artifact_type == "design_language" and a.status == "active")
      |> Repo.exists?()

    if has_design_language || has_design_language_artifact do
      # Check recent design nodes that may not reference the design language
      cutoff = DateTime.utc_now() |> DateTime.add(-7 * 86400)

      recent_design_count =
        HydraX.Product.DesignNode
        |> where([d], d.project_id == ^project_id and d.inserted_at > ^cutoff)
        |> Repo.aggregate(:count)

      if recent_design_count > 2 do
        {:work_needed,
         "#{recent_design_count} design nodes created in the last 7 days. " <>
         "Review whether they align with the established design language. " <>
         "Flag any inconsistencies.",
         :low}
      else
        :ok
      end
    else
      :ok
    end
  end

  # Catch-all — should not normally be reached now
  defp run_check(_project_id, _agent, _check), do: :ok

  # --- Execution ---

  defp execute_batch(%{paused: true} = state), do: state
  defp execute_batch(%{queued_work: []} = state), do: state

  defp execute_batch(state) do
    now = DateTime.utc_now()

    # Sort by numeric priority (descending = highest first)
    sorted = Enum.sort_by(state.queued_work, fn item ->
      Map.get(@priority_values, item.priority, 0)
    end, :desc)

    # Filter out agents on cooldown
    {executable, on_cooldown} =
      Enum.split_with(sorted, fn item ->
        last = Map.get(state.last_actions, item.agent)
        is_nil(last) || DateTime.diff(now, last, :second) >= @agent_cooldown_seconds
      end)

    # Execute up to @max_items_per_tick, one per agent max
    {to_execute, remaining} =
      executable
      |> Enum.reduce({[], MapSet.new()}, fn item, {acc, seen_agents} ->
        if MapSet.member?(seen_agents, item.agent) do
          {acc, seen_agents}
        else
          {[item | acc], MapSet.put(seen_agents, item.agent)}
        end
      end)
      |> then(fn {selected, _} ->
        selected = Enum.take(Enum.reverse(selected), @max_items_per_tick)
        selected_set = MapSet.new(selected, &{&1.agent, &1.check})
        remaining = Enum.reject(executable, &MapSet.member?(selected_set, {&1.agent, &1.check}))
        {selected, remaining}
      end)

    # Execute each item
    last_actions =
      Enum.reduce(to_execute, state.last_actions, fn work, acc ->
        execute_work_item(state.project_id, work)
        Map.put(acc, work.agent, now)
      end)

    %{state | queued_work: remaining ++ on_cooldown, last_actions: last_actions}
  end

  defp execute_work_item(project_id, %{check: :full_scan}) do
    Logger.info("[Initiative] Running coherence full scan for project #{project_id}")
    Coherence.full_scan(project_id)
  end

  defp execute_work_item(project_id, %{agent: agent, prompt: prompt}) when is_binary(prompt) do
    Logger.info("[Initiative] Queueing autonomous work for #{agent} on project #{project_id}")

    # Check trust level for auto-promotion
    project = Product.get_project!(project_id)

    effective_prompt =
      if project.trust_level == "standard" do
        prompt <> "\n\nIMPORTANT: Create all outputs as draft nodes requiring human approval."
      else
        prompt
      end

    execute_autonomous_work(project_id, agent, effective_prompt)
  end

  defp execute_work_item(_project_id, _work), do: :ok

  defp execute_autonomous_work(project_id, persona, prompt) do
    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(
        project_id,
        persona,
        %{
          "channel" => "autonomous",
          "external_ref" => "initiative_#{persona}",
          "title" => "#{String.capitalize(persona)} autonomous work",
          "metadata" => %{"source" => "initiative_engine"}
        }
      )

    {:ok, _result} =
      AgentBridge.submit_message(conversation, prompt, %{
        "autonomous" => true,
        "initiative_source" => true
      })

    :ok
  rescue
    err ->
      Logger.warning(
        "[Initiative] autonomous work failed for #{persona}: #{inspect(err)}"
      )

      :error
  end

  # --- Helpers ---

  defp over_budget?(project_id) do
    # Check if any of the project's agents have exceeded their daily soft warning threshold.
    # If so, pause autonomous work to avoid burning through budget.
    project = Product.get_project!(project_id)

    agent_ids =
      [
        project.researcher_agent_id,
        project.strategist_agent_id,
        project.architect_agent_id,
        project.designer_agent_id,
        project.memory_agent_id
      ]
      |> Enum.reject(&is_nil/1)

    Enum.any?(agent_ids, fn agent_id ->
      case HydraX.Budget.get_policy(agent_id) do
        nil ->
          false

        %{enabled: false} ->
          false

        %{daily_limit: limit, soft_warning_at: threshold}
        when is_number(limit) and is_number(threshold) ->
          try do
            snapshot = HydraX.Budget.usage_snapshot(agent_id, nil)
            daily_tokens = (snapshot && snapshot.daily_tokens) || 0
            daily_tokens >= limit * threshold
          rescue
            _ -> false
          end
      end
    end)
  end

  defp find_insights_without_decisions(project_id) do
    insights_with_decisions =
      HydraX.Product.GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and
          e.from_node_type == "insight" and
          e.to_node_type == "decision"
      )
      |> select([e], e.from_node_id)
      |> Repo.all()
      |> MapSet.new()

    HydraX.Product.Insight
    |> where([i], i.project_id == ^project_id and i.status in ["accepted", "draft"])
    |> Repo.all()
    |> Enum.reject(fn i -> MapSet.member?(insights_with_decisions, i.id) end)
  end

  defp last_coherence_scan_time(project_id) do
    HydraX.Product.GraphFlag
    |> where([f], f.project_id == ^project_id and f.source_agent == "coherence")
    |> order_by([f], desc: f.inserted_at)
    |> limit(1)
    |> select([f], f.inserted_at)
    |> Repo.one()
  end

  defp queue_work(state, agent, check, prompt, priority) do
    item = %{agent: agent, check: check, prompt: prompt, priority: priority}

    # Deduplicate: don't add if same agent+check already queued
    if Enum.any?(state.queued_work, &(&1.agent == agent && &1.check == check)) do
      state
    else
      %{state | queued_work: [item | state.queued_work]}
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp via(project_id) do
    {:via, Registry, {HydraX.Product.InitiativeRegistry, project_id}}
  end
end
