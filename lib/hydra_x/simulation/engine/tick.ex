defmodule HydraX.Simulation.Engine.Tick do
  @moduledoc """
  Single-tick execution logic.

  Each tick follows this sequence:
  1. Generate world events
  2. Deliver events to all agents (with LLM request collector)
  3. Wait for agents to reach initial decision (idle, deliberating, or negotiating)
  4. Collect pending LLM requests, batch dispatch via BatchInference
  5. Deliver LLM results to waiting agents
  6. Wait for all agents to settle to :idle
  7. Apply agent actions to world state
  8. Emit telemetry and broadcast tick completion
  """

  alias HydraX.Simulation.World.{World, Event, EventBus}
  alias HydraX.Simulation.Engine.BatchInference
  alias HydraX.Simulation.Registry, as: SimRegistry

  @settle_timeout_ms 5_000
  @llm_settle_timeout_ms 2_000

  @doc """
  Execute a single simulation tick.
  Returns :ok or {:error, reason}.

  Options:
  - :llm_fn - custom LLM function for testing (default: LLM.Router.complete)
  """
  @spec execute(String.t(), non_neg_integer(), keyword()) :: :ok | {:error, term()}
  def execute(sim_id, tick_number, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    try do
      # Set up LLM request collector for this tick
      collector = start_collector()

      # 1. Generate world events
      events = World.generate_events(sim_id)

      # 2. Deliver events to all agents with LLM callback
      agent_ids = SimRegistry.list_agents(sim_id)
      llm_callback = make_llm_callback(collector)
      set_agent_callbacks(sim_id, agent_ids, llm_callback)
      deliver_events(sim_id, agent_ids, events)

      # 3. Wait for agents to reach initial decision point
      #    (idle for routine/emotional, deliberating/negotiating for LLM-needing)
      await_initial_decisions(sim_id, agent_ids)

      # 4. Collect and dispatch LLM requests
      llm_requests = drain_collector(collector)
      llm_results = dispatch_llm_requests(llm_requests, opts)

      # 5. Deliver LLM results to waiting agents
      deliver_llm_results(sim_id, llm_results)

      # 6. Wait for all agents to settle to :idle
      await_agents_settled(sim_id, agent_ids)

      # 7. Collect actions and apply to world
      actions = collect_actions(sim_id, agent_ids)
      World.apply_actions(sim_id, actions)

      World.finalize_tick_events(sim_id)
      World.advance_tick(sim_id)

      # 8. Build tick data and broadcast
      duration_us = System.monotonic_time(:microsecond) - start_time
      tier_counts = count_tiers(actions)
      llm_call_count = length(llm_requests)

      tick_data = %{
        tick_number: tick_number,
        duration_us: duration_us,
        event_count: length(events),
        action_count: length(actions),
        tier_counts: tier_counts,
        llm_calls: llm_call_count,
        events: events,
        agent_state_changes: [],
        relationship_changes: [],
        new_relationships: [],
        removed_relationships: [],
        notable_events: Enum.take(events, 5),
        cost_cents: 0
      }

      EventBus.broadcast_tick_complete(sim_id, tick_data)

      :telemetry.execute(
        [:hydra_x, :simulation, :tick],
        %{duration_us: duration_us, event_count: length(events), llm_calls: llm_call_count},
        %{sim_id: sim_id, tick: tick_number, tiers: tier_counts}
      )

      stop_collector(collector)
      :ok
    rescue
      e -> {:error, {e, __STACKTRACE__}}
    end
  end

  # --- LLM Request Collector ---

  defp start_collector do
    {:ok, pid} = Agent.start_link(fn -> [] end)
    pid
  end

  defp stop_collector(pid) do
    Agent.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp make_llm_callback(collector) do
    fn request ->
      Agent.update(collector, fn requests -> [request | requests] end)
    end
  end

  defp drain_collector(collector) do
    Agent.get_and_update(collector, fn requests -> {Enum.reverse(requests), []} end)
  end

  # --- Agent callback injection ---

  defp set_agent_callbacks(_sim_id, _agent_ids, _callback) do
    # Callbacks are set at spawn time via Population/Runner.
    # This is a no-op — the callback was already injected when agents started.
    :ok
  end

  # --- Event delivery ---

  defp deliver_events(sim_id, agent_ids, events) do
    for agent_id <- agent_ids do
      case SimRegistry.lookup(sim_id, agent_id) do
        {:ok, pid} ->
          for event <- events do
            personalized = Event.personalize(event, get_agent_domain(pid))
            :gen_statem.cast(pid, {:world_event, personalized})
          end

        :error ->
          :ok
      end
    end
  end

  defp get_agent_domain(pid) do
    try do
      {_state, data} = :gen_statem.call(pid, :get_state, 1_000)
      data.persona.domain
    catch
      :exit, _ -> nil
    end
  end

  # --- Settling ---

  defp await_initial_decisions(sim_id, agent_ids) do
    # Wait until agents have processed events and reached a decision point:
    # :idle (routine/emotional already handled), :deliberating, or :negotiating
    deadline = System.monotonic_time(:millisecond) + @llm_settle_timeout_ms
    stable_states = [:idle, :recovering, :deliberating, :negotiating]
    do_await_states(sim_id, agent_ids, stable_states, deadline)
  end

  defp await_agents_settled(sim_id, agent_ids) do
    deadline = System.monotonic_time(:millisecond) + @settle_timeout_ms
    do_await_states(sim_id, agent_ids, [:idle, :recovering], deadline)
  end

  defp do_await_states(_sim_id, [], _target_states, _deadline), do: :ok

  defp do_await_states(sim_id, agent_ids, target_states, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      unsettled =
        Enum.filter(agent_ids, fn agent_id ->
          case SimRegistry.lookup(sim_id, agent_id) do
            {:ok, pid} ->
              try do
                {state, _data} = :gen_statem.call(pid, :get_state, 500)
                state not in target_states
              catch
                :exit, _ -> false
              end

            :error ->
              false
          end
        end)

      if unsettled == [] do
        :ok
      else
        Process.sleep(10)
        do_await_states(sim_id, unsettled, target_states, deadline)
      end
    end
  end

  # --- LLM dispatch ---

  defp dispatch_llm_requests([], _opts), do: []

  defp dispatch_llm_requests(requests, opts) do
    llm_fn = Keyword.get(opts, :llm_fn)
    batch_opts = if llm_fn, do: [llm_fn: llm_fn], else: []
    BatchInference.run(requests, batch_opts)
  end

  defp deliver_llm_results(sim_id, results) do
    for {agent_id, result} <- results, agent_id != nil do
      case SimRegistry.lookup(sim_id, agent_id) do
        {:ok, pid} ->
          :gen_statem.cast(pid, {:llm_result, result})

        :error ->
          :ok
      end
    end
  end

  # --- Action collection ---

  defp collect_actions(sim_id, agent_ids) do
    Enum.flat_map(agent_ids, fn agent_id ->
      case SimRegistry.lookup(sim_id, agent_id) do
        {:ok, pid} ->
          try do
            {_state, data} = :gen_statem.call(pid, :get_state, 1_000)
            history = :queue.to_list(data.tick_history)

            case List.last(history) do
              nil -> []
              action -> [{agent_id, action}]
            end
          catch
            :exit, _ -> []
          end

        :error ->
          []
      end
    end)
  end

  defp count_tiers(actions) do
    Enum.reduce(actions, %{routine: 0, emotional: 0, complex: 0, negotiation: 0}, fn
      {_id, %{method: :rules_engine}}, acc -> Map.update!(acc, :routine, &(&1 + 1))
      {_id, %{method: :emotional}}, acc -> Map.update!(acc, :emotional, &(&1 + 1))
      {_id, %{method: :cheap_llm}}, acc -> Map.update!(acc, :complex, &(&1 + 1))
      {_id, %{method: :frontier_llm}}, acc -> Map.update!(acc, :negotiation, &(&1 + 1))
      _, acc -> Map.update!(acc, :routine, &(&1 + 1))
    end)
  end
end
