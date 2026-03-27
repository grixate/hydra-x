defmodule HydraX.Simulation.Engine.Replay do
  @moduledoc """
  Replay a simulation from any tick by re-initializing world state
  from persisted tick snapshots.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Simulation.Schema.{SimTick, SimEvent}

  @doc """
  Load tick data for a simulation, optionally starting from a specific tick.
  Returns a list of tick maps in chronological order.
  """
  @spec load_ticks(integer(), keyword()) :: [map()]
  def load_ticks(simulation_id, opts \\ []) do
    from_tick = Keyword.get(opts, :from, 0)
    to_tick = Keyword.get(opts, :to)

    query =
      from t in SimTick,
        where: t.simulation_id == ^simulation_id and t.tick_number >= ^from_tick,
        order_by: [asc: t.tick_number]

    query =
      if to_tick do
        from t in query, where: t.tick_number <= ^to_tick
      else
        query
      end

    Repo.all(query)
    |> Enum.map(&tick_to_map/1)
  end

  @doc """
  Load events for a simulation within a tick range.
  """
  @spec load_events(integer(), keyword()) :: [map()]
  def load_events(simulation_id, opts \\ []) do
    from_tick = Keyword.get(opts, :from, 0)
    to_tick = Keyword.get(opts, :to)

    query =
      from e in SimEvent,
        where: e.simulation_id == ^simulation_id and e.tick >= ^from_tick,
        order_by: [asc: e.tick, asc: e.id]

    query =
      if to_tick do
        from e in query, where: e.tick <= ^to_tick
      else
        query
      end

    Repo.all(query)
    |> Enum.map(&event_to_map/1)
  end

  @doc """
  Build a replay timeline from persisted data.
  Returns a list of %{tick: N, events: [...], world_delta: %{}, tier_counts: %{}} maps.
  """
  @spec build_timeline(integer(), keyword()) :: [map()]
  def build_timeline(simulation_id, opts \\ []) do
    ticks = load_ticks(simulation_id, opts)
    events = load_events(simulation_id, opts)

    events_by_tick = Enum.group_by(events, & &1.tick)

    Enum.map(ticks, fn tick ->
      Map.put(tick, :events, Map.get(events_by_tick, tick.tick_number, []))
    end)
  end

  defp tick_to_map(%SimTick{} = t) do
    %{
      tick_number: t.tick_number,
      duration_us: t.duration_us,
      tier_counts: t.tier_counts || %{},
      llm_calls: t.llm_calls || 0,
      tokens_used: t.tokens_used || 0,
      world_delta: t.world_delta || %{}
    }
  end

  defp event_to_map(%SimEvent{} = e) do
    %{
      tick: e.tick,
      event_type: e.event_type,
      source: e.source,
      target: e.target,
      description: e.description,
      properties: e.properties || %{},
      stakes: e.stakes
    }
  end
end
