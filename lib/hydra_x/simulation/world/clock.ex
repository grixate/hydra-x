defmodule HydraX.Simulation.World.Clock do
  @moduledoc """
  Tick scheduler for simulations.

  Controls the pace of the simulation by scheduling tick execution at
  configurable intervals. Supports pause/resume and max tick limits.
  """

  use GenServer

  alias HydraX.Simulation.Engine.Tick
  alias HydraX.Simulation.World.EventBus

  defstruct [
    :sim_id,
    :max_ticks,
    :tick_interval_ms,
    :current_tick,
    :status,
    :tick_callback
  ]

  @type status :: :paused | :running | :completed | :failed

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
    state = %__MODULE__{
      sim_id: Keyword.fetch!(opts, :sim_id),
      max_ticks: Keyword.get(opts, :max_ticks, 40),
      tick_interval_ms: Keyword.get(opts, :tick_interval_ms, 500),
      current_tick: 0,
      status: :paused,
      tick_callback: Keyword.get(opts, :tick_callback)
    }

    {:ok, state}
  end

  # --- Public API ---

  @doc "Start or resume the clock."
  def start_clock(sim_id), do: GenServer.call(via(sim_id), :start)

  @doc "Pause the clock."
  def pause(sim_id), do: GenServer.call(via(sim_id), :pause)

  @doc "Get current clock status."
  def status(sim_id), do: GenServer.call(via(sim_id), :status)

  @doc "Get current tick number."
  def current_tick(sim_id), do: GenServer.call(via(sim_id), :current_tick)

  # --- GenServer callbacks ---

  @impl true
  def handle_call(:start, _from, %{status: :completed} = state) do
    {:reply, {:error, :already_completed}, state}
  end

  def handle_call(:start, _from, state) do
    schedule_next_tick(0)
    {:reply, :ok, %{state | status: :running}}
  end

  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{status: state.status, tick: state.current_tick, max_ticks: state.max_ticks}, state}
  end

  def handle_call(:current_tick, _from, state) do
    {:reply, state.current_tick, state}
  end

  @impl true
  def handle_info(:tick, %{status: :running} = state) do
    if state.current_tick >= state.max_ticks do
      EventBus.broadcast_lifecycle(state.sim_id, :completed)
      {:noreply, %{state | status: :completed}}
    else
      result = execute_tick(state)

      case result do
        :ok ->
          new_tick = state.current_tick + 1
          schedule_next_tick(state.tick_interval_ms)
          {:noreply, %{state | current_tick: new_tick}}

        {:error, _reason} ->
          EventBus.broadcast_lifecycle(state.sim_id, :failed)
          {:noreply, %{state | status: :failed}}
      end
    end
  end

  def handle_info(:tick, state) do
    # Ignore tick if paused or completed
    {:noreply, state}
  end

  # --- Private ---

  defp execute_tick(state) do
    if state.tick_callback do
      state.tick_callback.(state.sim_id, state.current_tick)
    else
      Tick.execute(state.sim_id, state.current_tick)
    end
  end

  defp schedule_next_tick(delay_ms) do
    Process.send_after(self(), :tick, delay_ms)
  end

  defp via(sim_id) do
    {:via, Registry, {HydraX.Simulation.Registry, {:clock, sim_id}}}
  end
end
