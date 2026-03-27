defmodule HydraX.Simulation.World.World do
  @moduledoc """
  World state GenServer with ETS-backed entity and relationship storage.

  The world holds the global simulation state: entities, resources, market
  conditions, active events, and the relationship graph. ETS is used for
  concurrent read access during ticks and atomic per-key writes.
  """

  use GenServer

  alias HydraX.Simulation.World.Event

  defstruct [
    :sim_id,
    :tick,
    :entities,
    :relationships,
    :active_events,
    :global_state,
    :event_history,
    :config,
    :rng_seed
  ]

  @type t :: %__MODULE__{}

  # --- Lifecycle ---

  def start_link(opts) do
    sim_id = Keyword.fetch!(opts, :sim_id)
    name = Keyword.get(opts, :name, via(sim_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    sim_id = Keyword.fetch!(opts, :sim_id)

    %{
      id: {__MODULE__, sim_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @impl true
  def init(opts) do
    sim_id = Keyword.fetch!(opts, :sim_id)

    entities_table =
      :ets.new(:"sim_entities_#{sim_id}", [:set, :public, :named_table, read_concurrency: true])

    rels_table =
      :ets.new(:"sim_rels_#{sim_id}", [:bag, :public, :named_table, read_concurrency: true])

    rng_seed =
      case Keyword.get(opts, :rng_seed) do
        nil -> :rand.seed(:exsss)
        seed -> :rand.seed(:exsss, seed)
      end

    state = %__MODULE__{
      sim_id: sim_id,
      tick: 0,
      entities: entities_table,
      relationships: rels_table,
      active_events: [],
      global_state: Keyword.get(opts, :initial_state, default_global_state()),
      event_history: [],
      config: Keyword.get(opts, :config),
      rng_seed: rng_seed
    }

    # Insert any initial entities
    for entity <- Keyword.get(opts, :initial_entities, []) do
      :ets.insert(entities_table, entity)
    end

    for rel <- Keyword.get(opts, :initial_relationships, []) do
      :ets.insert(rels_table, rel)
    end

    {:ok, state}
  end

  # --- Public API ---

  @doc "Get the current tick number."
  def current_tick(sim_id), do: GenServer.call(via(sim_id), :current_tick)

  @doc "Get the full world state snapshot."
  def snapshot(sim_id), do: GenServer.call(via(sim_id), :snapshot)

  @doc "Advance to the next tick."
  def advance_tick(sim_id), do: GenServer.call(via(sim_id), :advance_tick)

  @doc "Get the global state map."
  def global_state(sim_id), do: GenServer.call(via(sim_id), :global_state)

  @doc "Update global state with a merge map."
  def update_global_state(sim_id, updates),
    do: GenServer.call(via(sim_id), {:update_global_state, updates})

  @doc "Set active events for the current tick."
  def set_active_events(sim_id, events),
    do: GenServer.call(via(sim_id), {:set_active_events, events})

  @doc "Get active events for the current tick."
  def active_events(sim_id), do: GenServer.call(via(sim_id), :active_events)

  @doc "Push events to history and clear active events."
  def finalize_tick_events(sim_id), do: GenServer.call(via(sim_id), :finalize_tick_events)

  @doc "Generate world events for the current tick based on global state and config."
  def generate_events(sim_id), do: GenServer.call(via(sim_id), :generate_events)

  @doc "Apply a list of agent actions to the world state."
  def apply_actions(sim_id, actions), do: GenServer.call(via(sim_id), {:apply_actions, actions})

  @doc "Get a world state delta for the current tick (for persistence)."
  def tick_delta(sim_id), do: GenServer.call(via(sim_id), :tick_delta)

  # --- Entity API (direct ETS access for concurrent reads) ---

  @doc "Insert or update an entity in the world."
  def put_entity(sim_id, entity_id, type, properties) do
    table = entities_table_name(sim_id)
    :ets.insert(table, {entity_id, type, properties})
    :ok
  end

  @doc "Get an entity by ID."
  def get_entity(sim_id, entity_id) do
    table = entities_table_name(sim_id)

    case :ets.lookup(table, entity_id) do
      [{^entity_id, type, properties}] -> {:ok, {entity_id, type, properties}}
      [] -> :error
    end
  end

  @doc "List all entities."
  def list_entities(sim_id) do
    table = entities_table_name(sim_id)
    :ets.tab2list(table)
  end

  @doc "Add a relationship between entities."
  def put_relationship(sim_id, from_id, to_id, rel_type, weight \\ 1.0) do
    table = rels_table_name(sim_id)
    :ets.insert(table, {from_id, to_id, rel_type, weight})
    :ok
  end

  @doc "Get all relationships from an entity."
  def relationships_from(sim_id, from_id) do
    table = rels_table_name(sim_id)
    :ets.match_object(table, {from_id, :_, :_, :_})
  end

  @doc "Get all relationships of a specific type from an entity."
  def relationships_of_type(sim_id, from_id, rel_type) do
    table = rels_table_name(sim_id)
    :ets.match_object(table, {from_id, :_, rel_type, :_})
  end

  @doc "List all relationships."
  def list_relationships(sim_id) do
    table = rels_table_name(sim_id)
    :ets.tab2list(table)
  end

  # --- GenServer callbacks ---

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick, state}
  end

  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      sim_id: state.sim_id,
      tick: state.tick,
      global_state: state.global_state,
      active_events: state.active_events,
      entity_count: :ets.info(state.entities, :size),
      relationship_count: :ets.info(state.relationships, :size)
    }

    {:reply, snapshot, state}
  end

  def handle_call(:advance_tick, _from, state) do
    new_tick = state.tick + 1
    {:reply, new_tick, %{state | tick: new_tick}}
  end

  def handle_call(:global_state, _from, state) do
    {:reply, state.global_state, state}
  end

  def handle_call({:update_global_state, updates}, _from, state) do
    new_global = Map.merge(state.global_state, updates)
    {:reply, :ok, %{state | global_state: new_global}}
  end

  def handle_call({:set_active_events, events}, _from, state) do
    {:reply, :ok, %{state | active_events: events}}
  end

  def handle_call(:active_events, _from, state) do
    {:reply, state.active_events, state}
  end

  def handle_call(:finalize_tick_events, _from, state) do
    # Keep last 10 ticks of history
    history = Enum.take(state.active_events ++ state.event_history, 200)
    {:reply, :ok, %{state | active_events: [], event_history: history}}
  end

  def handle_call(:generate_events, _from, state) do
    {events, new_rng} = do_generate_events(state)
    state = %{state | rng_seed: new_rng, active_events: events}
    {:reply, events, state}
  end

  def handle_call({:apply_actions, actions}, _from, state) do
    new_global = apply_action_effects(actions, state.global_state)
    {:reply, :ok, %{state | global_state: new_global}}
  end

  def handle_call(:tick_delta, _from, state) do
    delta = %{
      tick: state.tick,
      global_state: state.global_state,
      active_event_count: length(state.active_events),
      entity_count: :ets.info(state.entities, :size),
      relationship_count: :ets.info(state.relationships, :size)
    }

    {:reply, delta, state}
  end

  # --- Private: Event generation ---

  defp do_generate_events(state) do
    config = state.config || %{}
    event_frequency = Map.get(config, :event_frequency, 0.3)
    crisis_probability = Map.get(config, :crisis_probability, 0.05)
    volatility = Map.get(config, :market_volatility, 0.5)
    rng = state.rng_seed

    # Determine how many events this tick (1-3 based on frequency)
    {roll, rng} = :rand.uniform_s(rng)
    event_count = if roll < event_frequency, do: 1 + floor(volatility * 2), else: 0

    {events, rng} =
      Enum.reduce(1..max(event_count, 0)//1, {[], rng}, fn _, {acc, rng} ->
        {is_crisis, rng} = roll_crisis(rng, crisis_probability)
        {event_type, rng} = pick_event_type(rng, is_crisis)
        {stakes, rng} = roll_stakes(rng, volatility)

        event =
          Event.new(%{
            type: event_type,
            source: :world,
            stakes: stakes,
            emotional_valence: event_valence(event_type),
            is_crisis?: is_crisis,
            is_threat?: event_type in [:security_breach, :lawsuit, :market_crash, :pr_crisis],
            is_provocation?: event_type in [:competitor_move, :conflict_escalation],
            is_opportunity?:
              event_type in [:partnership_offer, :demand_surge, :innovation_breakthrough],
            is_windfall?: event_type == :demand_surge and stakes > 0.7,
            tick: state.tick,
            description: describe_event(event_type, is_crisis)
          })

        {[event | acc], rng}
      end)

    {Enum.reverse(events), rng}
  end

  defp roll_crisis(rng, probability) do
    {roll, rng} = :rand.uniform_s(rng)
    {roll < probability, rng}
  end

  @normal_events [
    :market_shift,
    :price_change,
    :competitor_move,
    :product_launch,
    :budget_pressure,
    :talent_departure,
    :regulation_change,
    :media_coverage,
    :investor_sentiment,
    :partnership_offer,
    :innovation_breakthrough,
    :demand_surge,
    :supply_disruption
  ]

  @crisis_events [:pr_crisis, :security_breach, :lawsuit, :market_crash]

  defp pick_event_type(rng, true) do
    {index, rng} = :rand.uniform_s(length(@crisis_events), rng)
    {Enum.at(@crisis_events, index - 1), rng}
  end

  defp pick_event_type(rng, false) do
    {index, rng} = :rand.uniform_s(length(@normal_events), rng)
    {Enum.at(@normal_events, index - 1), rng}
  end

  defp roll_stakes(rng, volatility) do
    {base, rng} = :rand.uniform_s(rng)
    stakes = min(1.0, base * (0.3 + volatility * 0.7))
    {Float.round(stakes, 2), rng}
  end

  defp event_valence(type) do
    case type do
      t when t in [:demand_surge, :innovation_breakthrough, :partnership_offer] ->
        :positive

      t when t in [:market_crash, :lawsuit, :pr_crisis, :security_breach, :talent_departure] ->
        :negative

      _ ->
        :neutral
    end
  end

  defp describe_event(type, is_crisis) do
    prefix = if is_crisis, do: "CRISIS: ", else: ""
    "#{prefix}#{type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()}"
  end

  # --- Private: Action effects ---

  defp apply_action_effects(actions, global_state) do
    Enum.reduce(actions, global_state, fn {_agent_id, action}, gs ->
      case action.type do
        :aggressive_response ->
          Map.update(gs, :market_tension, 0.1, &min(1.0, &1 + 0.05))

        :innovative_proposal ->
          Map.update(gs, :innovation_index, 0.5, &min(1.0, &1 + 0.03))

        :seek_consensus ->
          Map.update(gs, :market_tension, 0.0, &max(0.0, &1 - 0.02))

        :cost_cutting ->
          Map.update(gs, :market_sentiment, 0.5, &max(0.0, &1 - 0.05))

        _ ->
          gs
      end
    end)
  end

  defp default_global_state do
    %{
      market_sentiment: 0.5,
      market_tension: 0.0,
      innovation_index: 0.5,
      regulatory_pressure: 0.3,
      economic_growth: 0.5
    }
  end

  # --- Private: naming ---

  defp via(sim_id) do
    {:via, Registry, {HydraX.Simulation.Registry, {:world, sim_id}}}
  end

  defp entities_table_name(sim_id), do: :"sim_entities_#{sim_id}"
  defp rels_table_name(sim_id), do: :"sim_rels_#{sim_id}"
end
