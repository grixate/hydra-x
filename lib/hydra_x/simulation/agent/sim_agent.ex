defmodule HydraX.Simulation.Agent.SimAgent do
  @moduledoc """
  The personality finite state machine — core of the simulation engine.

  Each SimAgent is a `gen_statem` process with behavioral states that determine
  how the agent processes world events. The three-tier decision architecture
  routes most decisions through a deterministic rules engine, only escalating
  to LLM inference for genuinely novel or complex situations.

  ## States (spec §3)

  | State          | Description                                    | LLM tier |
  |----------------|------------------------------------------------|----------|
  | `:idle`        | Drains event queue, processes modifier decay    | None     |
  | `:observing`   | Transient: classifies one event into a tier     | None     |
  | `:reacting`    | Emotional fast path via trait tables             | None     |
  | `:acting`      | Broadcasts action, updates beliefs/relationships | None     |
  | `:deliberating`| Awaiting cheap LLM result                        | Cheap    |
  | `:negotiating` | Awaiting frontier LLM result                     | Frontier |
  | `:recovering`  | Post-crisis cooldown (N ticks)                   | None     |
  """

  @behaviour :gen_statem

  alias HydraX.Simulation.Agent.{Traits, DecisionRouter, Action, Persona}
  alias HydraX.Simulation.World.Event

  @max_event_queue 20
  @max_beliefs 100
  @recovery_ticks 3
  @modifier_half_life 8

  defstruct [
    :id,
    :sim_id,
    :persona,
    :modifier,
    :modifier_set_tick,
    :beliefs,
    :relationships,
    :pending_action,
    :event_queue,
    :current_tick,
    :tick_history,
    :llm_call_count,
    :rng_seed,
    :novelty_threshold,
    :stakes_threshold,
    :recovery_ticks_remaining,
    :llm_request_callback
  ]

  @type t :: %__MODULE__{}

  # --- Lifecycle ---

  def start_link(opts) do
    sim_id = Keyword.fetch!(opts, :sim_id)
    agent_id = Keyword.fetch!(opts, :agent_id)
    _persona = Keyword.fetch!(opts, :persona)

    name =
      case Keyword.get(opts, :name) do
        nil -> via(sim_id, agent_id)
        name -> name
      end

    :gen_statem.start_link(name, __MODULE__, opts, [])
  end

  def child_spec(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)

    %{
      id: {__MODULE__, agent_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @impl true
  def init(opts) do
    rng = :rand.seed(:exsss, opts[:seed] || :erlang.phash2(opts[:agent_id]))
    persona = opts[:persona]

    # Apply trait noise at spawn time (spec §2.3)
    {noisy_traits, rng} = Traits.apply_noise(persona.traits, rng)
    persona = %{persona | traits: noisy_traits}

    data = %__MODULE__{
      id: opts[:agent_id],
      sim_id: opts[:sim_id],
      persona: persona,
      modifier: nil,
      modifier_set_tick: nil,
      beliefs: [],
      relationships: %{},
      pending_action: nil,
      event_queue: :queue.new(),
      current_tick: 0,
      tick_history: :queue.new(),
      llm_call_count: 0,
      rng_seed: rng,
      novelty_threshold: opts[:novelty_threshold] || 2,
      stakes_threshold: opts[:stakes_threshold] || 0.7,
      recovery_ticks_remaining: 0,
      llm_request_callback: opts[:llm_request_callback]
    }

    {:ok, :idle, data}
  end

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  # --- Public API ---

  def get_state(sim_id, agent_id) do
    :gen_statem.call(via(sim_id, agent_id), :get_state)
  end

  def send_event(sim_id, agent_id, event) do
    :gen_statem.cast(via(sim_id, agent_id), {:world_event, event})
  end

  def deliver_llm_result(sim_id, agent_id, result) do
    :gen_statem.cast(via(sim_id, agent_id), {:llm_result, result})
  end

  @doc "Advance the agent's tick clock. Processes modifier decay and event queue."
  def advance_tick(sim_id, agent_id, tick) do
    :gen_statem.cast(via(sim_id, agent_id), {:advance_tick, tick})
  end

  # ══════════════════════════════════════════════════
  # State: idle
  # ══════════════════════════════════════════════════

  def idle(:enter, _old_state, data) do
    # FIX: drain queue continuously — schedule drain attempt on every enter
    drain_or_stay(data)
  end

  def idle(:timeout, {:drain_event, event}, data) do
    # FIX: if event is irrelevant, process_event returns {:keep_state, data}
    # which stays in :idle but does NOT re-trigger the enter callback.
    # We must explicitly try to drain the next event on :keep_state.
    case process_event(data, event) do
      {:next_state, _, _, _} = transition ->
        transition

      {:keep_state, data} ->
        # Event was irrelevant — try next queued event
        drain_or_stay(data)
    end
  end

  def idle(:cast, {:world_event, %Event{} = event}, data) do
    process_event(data, event)
  end

  def idle(:cast, {:advance_tick, tick}, data) do
    data = handle_advance_tick(data, tick)
    {:keep_state, data}
  end

  def idle(:cast, {:llm_result, _result}, data) do
    # Stale LLM result arriving after we've moved on — discard
    {:keep_state, data}
  end

  def idle({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:idle, data}}]}
  end

  # ══════════════════════════════════════════════════
  # State: observing
  # ══════════════════════════════════════════════════

  def observing(:enter, _old_state, data) do
    {:keep_state, data}
  end

  def observing(:internal, {:evaluate, event}, data) do
    state_map = %{
      beliefs: data.beliefs,
      current_tick: data.current_tick,
      novelty_threshold: data.novelty_threshold,
      stakes_threshold: data.stakes_threshold
    }

    classification = DecisionRouter.classify(data.persona, event, state_map)

    case classification do
      :routine ->
        action = resolve_routine_action(data, event)
        {:next_state, :acting, %{data | pending_action: action}}

      :emotional ->
        {:next_state, :reacting, data, [{:next_event, :internal, {:react_to, event}}]}

      :complex ->
        {:next_state, :deliberating, data, [{:next_event, :internal, {:deliberate, event}}]}

      :negotiation ->
        {:next_state, :negotiating, data, [{:next_event, :internal, {:negotiate, event}}]}
    end
  end

  def observing(:cast, {:world_event, event}, data) do
    {:keep_state, enqueue_event(data, event)}
  end

  def observing(:cast, {:advance_tick, tick}, data) do
    {:keep_state, handle_advance_tick(data, tick)}
  end

  def observing(:cast, {:llm_result, _}, data), do: {:keep_state, data}

  def observing({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:observing, data}}]}
  end

  # ══════════════════════════════════════════════════
  # State: reacting
  # ══════════════════════════════════════════════════

  def reacting(:enter, _old_state, data) do
    {:keep_state, data}
  end

  def reacting(:internal, {:react_to, event}, data) do
    {action_type, new_rng} =
      Traits.emotional_response(data.persona.traits, event, data.modifier, data.rng_seed)

    action =
      Action.new(action_type, %{
        event_id: event.id,
        event_type: event.type,
        method: :emotional
      })

    new_modifier = set_modifier(data, event, :emotional)

    data = %{
      data
      | pending_action: action,
        rng_seed: new_rng,
        modifier: new_modifier,
        modifier_set_tick:
          if(new_modifier != data.modifier, do: data.current_tick, else: data.modifier_set_tick)
    }

    {:next_state, :acting, data}
  end

  # FIX: added missing handlers for reacting state
  def reacting(:cast, {:world_event, event}, data) do
    {:keep_state, enqueue_event(data, event)}
  end

  def reacting(:cast, {:advance_tick, tick}, data) do
    {:keep_state, handle_advance_tick(data, tick)}
  end

  def reacting(:cast, {:llm_result, _}, data), do: {:keep_state, data}

  def reacting({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:reacting, data}}]}
  end

  # ══════════════════════════════════════════════════
  # State: deliberating
  # ══════════════════════════════════════════════════

  def deliberating(:enter, _old_state, data) do
    {:keep_state, data}
  end

  def deliberating(:internal, {:deliberate, event}, data) do
    if data.llm_request_callback do
      data.llm_request_callback.(%{
        agent_id: data.id,
        sim_id: data.sim_id,
        tier: :cheap,
        event: event,
        persona: data.persona,
        beliefs: data.beliefs,
        modifier: data.modifier
      })

      {:keep_state, %{data | pending_action: {:awaiting_llm, event}},
       [{:state_timeout, 15_000, :llm_timeout}]}
    else
      action = resolve_routine_action(data, event)
      {:next_state, :acting, %{data | pending_action: action}}
    end
  end

  def deliberating(:cast, {:llm_result, {:ok, decision}}, data) do
    action = Action.from_llm_decision(decision, data.persona)
    action = %{action | source_event_type: extract_pending_event_type(data)}
    data = %{data | pending_action: action, llm_call_count: data.llm_call_count + 1}
    {:next_state, :acting, data}
  end

  def deliberating(:cast, {:llm_result, {:error, _reason}}, data) do
    event = extract_pending_event(data)
    action = resolve_routine_action(data, event)
    {:next_state, :acting, %{data | pending_action: action}}
  end

  def deliberating(:state_timeout, :llm_timeout, data) do
    event = extract_pending_event(data)
    action = resolve_routine_action(data, event)
    {:next_state, :acting, %{data | pending_action: action}}
  end

  def deliberating(:cast, {:world_event, event}, data) do
    {:keep_state, enqueue_event(data, event)}
  end

  def deliberating(:cast, {:advance_tick, tick}, data) do
    {:keep_state, handle_advance_tick(data, tick)}
  end

  def deliberating({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:deliberating, data}}]}
  end

  # ══════════════════════════════════════════════════
  # State: negotiating
  # ══════════════════════════════════════════════════

  def negotiating(:enter, _old_state, data) do
    {:keep_state, data}
  end

  def negotiating(:internal, {:negotiate, event}, data) do
    if data.llm_request_callback do
      data.llm_request_callback.(%{
        agent_id: data.id,
        sim_id: data.sim_id,
        tier: :frontier,
        event: event,
        persona: data.persona,
        beliefs: data.beliefs,
        relationships: data.relationships,
        counterpart_id: event.target_agent_id,
        modifier: data.modifier
      })

      {:keep_state, %{data | pending_action: {:awaiting_llm, event}},
       [{:state_timeout, 30_000, :llm_timeout}]}
    else
      action = Action.new(:defer_decision, %{reason: "no_llm_callback", method: :rules_engine})
      {:next_state, :acting, %{data | pending_action: action}}
    end
  end

  def negotiating(:cast, {:llm_result, {:ok, decision}}, data) do
    action = Action.from_llm_decision(decision, data.persona)
    action = %{action | source_event_type: extract_pending_event_type(data)}
    data = %{data | pending_action: action, llm_call_count: data.llm_call_count + 1}
    {:next_state, :acting, data}
  end

  def negotiating(:cast, {:llm_result, {:error, _reason}}, data) do
    action = Action.new(:defer_decision, %{reason: "negotiation_failed", method: :rules_engine})
    {:next_state, :acting, %{data | pending_action: action}}
  end

  def negotiating(:state_timeout, :llm_timeout, data) do
    action = Action.new(:defer_decision, %{reason: "negotiation_timeout", method: :rules_engine})
    {:next_state, :acting, %{data | pending_action: action}}
  end

  def negotiating(:cast, {:world_event, event}, data) do
    {:keep_state, enqueue_event(data, event)}
  end

  def negotiating(:cast, {:advance_tick, tick}, data) do
    {:keep_state, handle_advance_tick(data, tick)}
  end

  def negotiating({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:negotiating, data}}]}
  end

  # ══════════════════════════════════════════════════
  # State: acting
  # ══════════════════════════════════════════════════

  def acting(:enter, _old_state, data) do
    {:keep_state, data, [{:timeout, 0, :execute_action}]}
  end

  def acting(:timeout, :execute_action, data) do
    action = data.pending_action

    # 1. Broadcast action to world
    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "simulation:#{data.sim_id}",
      {:agent_action, data.id, action}
    )

    # 2. Add belief for own action
    data = add_belief(data, :own_action, action.type, data.current_tick)

    # 3. Update relationships (spec §4.5)
    data = update_relationships(data, action)

    # 4. Record in tick history
    data = push_tick_history(data, action)

    # 5. Update RNG from process dict (set by resolve_routine_action)
    data = flush_rng(data)

    # 6. Determine if crisis action → recovering, else idle
    is_crisis_action =
      action.source_event_type in [:pr_crisis, :security_breach, :lawsuit, :market_crash]

    if is_crisis_action do
      {:next_state, :recovering,
       %{data | pending_action: nil, recovery_ticks_remaining: @recovery_ticks}}
    else
      {:next_state, :idle, %{data | pending_action: nil}}
    end
  end

  # FIX: added missing handlers for acting state
  def acting(:cast, {:world_event, event}, data) do
    {:keep_state, enqueue_event(data, event)}
  end

  def acting(:cast, {:advance_tick, _tick}, data) do
    # Acting is transient (instant timeout) — safe to ignore tick during execution
    {:keep_state, data}
  end

  def acting(:cast, {:llm_result, _}, data), do: {:keep_state, data}

  def acting({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:acting, data}}]}
  end

  # ══════════════════════════════════════════════════
  # State: recovering
  # ══════════════════════════════════════════════════

  def recovering(:enter, _old_state, data) do
    {:keep_state, %{data | modifier: :stressed, modifier_set_tick: data.current_tick}}
  end

  def recovering(:cast, {:advance_tick, tick}, data) do
    # FIX: also run handle_advance_tick for modifier decay
    data = handle_advance_tick(data, tick)
    data = %{data | recovery_ticks_remaining: data.recovery_ticks_remaining - 1}

    if data.recovery_ticks_remaining <= 0 do
      {:next_state, :idle, %{data | modifier: nil, modifier_set_tick: nil}}
    else
      {:keep_state, data}
    end
  end

  def recovering(:cast, {:world_event, %Event{is_crisis?: true} = event}, data) do
    role_cat = Persona.role_category(data.persona.domain)

    relevance =
      Traits.assess_relevance(data.persona.traits, event,
        role_category: role_cat,
        beliefs: data.beliefs,
        current_tick: data.current_tick
      )

    if relevance > 0.8 do
      {:next_state, :observing, data, [{:next_event, :internal, {:evaluate, event}}]}
    else
      {:keep_state, enqueue_event(data, event)}
    end
  end

  def recovering(:cast, {:world_event, event}, data) do
    {:keep_state, enqueue_event(data, event)}
  end

  # FIX: added missing handler
  def recovering(:cast, {:llm_result, _}, data), do: {:keep_state, data}

  def recovering({:call, from}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:recovering, data}}]}
  end

  # ══════════════════════════════════════════════════
  # Private: Event processing
  # ══════════════════════════════════════════════════

  defp process_event(data, %Event{} = event) do
    role_cat = Persona.role_category(data.persona.domain)

    relevance =
      Traits.assess_relevance(data.persona.traits, event,
        role_category: role_cat,
        beliefs: data.beliefs,
        current_tick: data.current_tick
      )

    if relevance >= 0.2 do
      category = Action.classify_event_category(event.type)
      data = add_belief(data, category, event.type, data.current_tick)

      {:next_state, :observing, %{data | pending_action: nil},
       [{:next_event, :internal, {:evaluate, event}}]}
    else
      {:keep_state, data}
    end
  end

  # FIX: idle enter + drain needs a helper that schedules next drain or stays
  defp drain_or_stay(data) do
    case :queue.out(data.event_queue) do
      {{:value, event}, rest} ->
        data = %{data | event_queue: rest}
        {:keep_state, data, [{:timeout, 0, {:drain_event, event}}]}

      {:empty, _} ->
        {:keep_state, data}
    end
  end

  # ══════════════════════════════════════════════════
  # Private: Routine action resolution
  # ══════════════════════════════════════════════════

  defp resolve_routine_action(data, event) do
    role_cat = Persona.role_category(data.persona.domain)
    options = Action.available_for(event.type)

    relevance =
      Traits.assess_relevance(data.persona.traits, event,
        role_category: role_cat,
        beliefs: data.beliefs,
        current_tick: data.current_tick
      )

    event_source_rel = get_event_source_relationship(data, event)

    weights =
      Enum.map(options, fn option ->
        w =
          Traits.compute_weight(
            data.persona.traits,
            option,
            data.modifier,
            relevance,
            event_source_rel
          )

        {option, w}
      end)

    {selected, new_rng} = Traits.weighted_random_select(weights, data.rng_seed)

    # Store updated RNG in process dict — flushed in acting state
    Process.put(:sim_agent_rng, new_rng)

    Action.new(selected, %{
      event_id: event.id,
      event_type: event.type,
      method: :rules_engine
    })
  end

  defp get_event_source_relationship(data, %Event{source: {:agent, agent_id}}) do
    Map.get(data.relationships, agent_id)
  end

  defp get_event_source_relationship(_data, _event), do: nil

  # ══════════════════════════════════════════════════
  # Private: Advance tick processing
  # ══════════════════════════════════════════════════

  defp handle_advance_tick(data, tick) do
    data = %{data | current_tick: tick}
    maybe_decay_modifier(data)
  end

  defp maybe_decay_modifier(%{modifier: nil} = data), do: data
  defp maybe_decay_modifier(%{modifier_set_tick: nil} = data), do: data

  defp maybe_decay_modifier(data) do
    ticks_elapsed = data.current_tick - data.modifier_set_tick

    if ticks_elapsed > 0 do
      p_clear = 1.0 - :math.pow(0.5, ticks_elapsed / @modifier_half_life)
      {roll, new_rng} = :rand.uniform_s(data.rng_seed)
      data = %{data | rng_seed: new_rng}

      if roll < p_clear do
        %{data | modifier: nil, modifier_set_tick: nil}
      else
        data
      end
    else
      data
    end
  end

  # ══════════════════════════════════════════════════
  # Private: Modifier setting (spec §6.1)
  # ══════════════════════════════════════════════════

  defp set_modifier(data, %Event{} = event, _source) do
    new_mod =
      cond do
        event.is_crisis? or event.is_threat? -> :stressed
        event.is_provocation? and data.persona.traits.emotional_reactivity > 0.6 -> :stressed
        event.is_windfall? and data.modifier == :stressed -> nil
        event.is_windfall? -> :confident
        true -> data.modifier
      end

    resolve_modifier_priority(data.modifier, new_mod)
  end

  @modifier_priority %{stressed: 4, uncertain: 3, confident: 2, aligned: 1}

  defp resolve_modifier_priority(current, new) do
    current_p = Map.get(@modifier_priority, current, 0)
    new_p = Map.get(@modifier_priority, new, 0)
    if new_p >= current_p, do: new, else: current
  end

  # ══════════════════════════════════════════════════
  # Private: Event queue (spec §3.3)
  # ══════════════════════════════════════════════════

  defp enqueue_event(data, event) do
    queue = data.event_queue

    queue =
      if :queue.len(queue) >= @max_event_queue do
        {_dropped, rest} = :queue.out(queue)
        rest
      else
        queue
      end

    %{data | event_queue: :queue.in(event, queue)}
  end

  # ══════════════════════════════════════════════════
  # Private: Beliefs (spec §4.6)
  # ══════════════════════════════════════════════════

  defp add_belief(data, tag, value, tick) do
    belief = {tag, value, tick}
    beliefs = [belief | data.beliefs] |> Enum.take(@max_beliefs)
    %{data | beliefs: beliefs}
  end

  # ══════════════════════════════════════════════════
  # Private: Relationships (spec §4.5)
  # ══════════════════════════════════════════════════

  defp update_relationships(data, %Action{} = action) do
    target_id =
      Map.get(action.properties, :target_agent_id) ||
        Map.get(action.properties, :counterpart_id)

    if target_id do
      {sent_delta, trust_delta} = Action.relationship_delta(action.type)
      current = Map.get(data.relationships, target_id, %{sentiment: 0.0, trust: 0.5})

      updated = %{
        sentiment: clamp(current.sentiment + sent_delta, -1.0, 1.0),
        trust: clamp(current.trust + trust_delta, 0.0, 1.0)
      }

      %{data | relationships: Map.put(data.relationships, target_id, updated)}
    else
      data
    end
  end

  defp clamp(value, min_val, max_val), do: max(min_val, min(max_val, value))

  # ══════════════════════════════════════════════════
  # Private: Tick history
  # ══════════════════════════════════════════════════

  defp push_tick_history(data, action) do
    entry = %{
      type: action.type,
      method: action.method,
      source_event_type: action.source_event_type,
      decided_at: action.decided_at
    }

    history = :queue.in(entry, data.tick_history)

    history =
      if :queue.len(history) > 20 do
        {_dropped, rest} = :queue.out(history)
        rest
      else
        history
      end

    %{data | tick_history: history}
  end

  # ══════════════════════════════════════════════════
  # Private: Helpers
  # ══════════════════════════════════════════════════

  defp flush_rng(data) do
    case Process.get(:sim_agent_rng) do
      nil ->
        data

      new_rng ->
        Process.delete(:sim_agent_rng)
        %{data | rng_seed: new_rng}
    end
  end

  defp extract_pending_event(data) do
    case data.pending_action do
      {:awaiting_llm, event} -> event
      _ -> Event.new(%{type: :unknown})
    end
  end

  defp extract_pending_event_type(data) do
    case data.pending_action do
      {:awaiting_llm, event} -> event.type
      _ -> nil
    end
  end

  defp via(sim_id, agent_id) do
    {:via, Registry, {HydraX.Simulation.Registry, {sim_id, agent_id}}}
  end
end
