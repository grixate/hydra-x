defmodule HydraX.Simulation.Engine.Runner do
  @moduledoc """
  Simulation lifecycle orchestrator.

  Manages the full lifecycle of a simulation:
  setup → seed → run → complete/fail

  Coordinates the World, Clock, and SimAgent processes through
  the simulation supervisor.
  """

  alias HydraX.Simulation.Config
  alias HydraX.Simulation.Registry, as: SimRegistry
  alias HydraX.Simulation.Agent.Population
  alias HydraX.Simulation.World.{World, Clock, EventBus}

  @type sim_state :: %{
          sim_id: String.t(),
          config: Config.t(),
          status: :configuring | :seeding | :running | :paused | :completed | :failed,
          supervisor: pid() | nil,
          personas: [Persona.t()],
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  @doc """
  Start a new simulation with the given configuration and personas.

  Starts the supervision tree (World, Clock, agents) and returns the sim_id.
  """
  @spec start(Config.t(), [Persona.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def start(%Config{} = config, personas, opts \\ []) do
    sim_id = Keyword.get(opts, :sim_id, generate_sim_id())

    with {:ok, _config} <- wrap_config_error(Config.validate(config)),
         :ok <- start_world(sim_id, config, opts),
         {:ok, _agent_ids} <- spawn_agents(sim_id, personas, config, opts),
         :ok <- start_clock(sim_id, config, opts) do
      EventBus.broadcast_lifecycle(sim_id, :started)

      {:ok, sim_id}
    else
      {:error, reason} ->
        cleanup(sim_id)
        {:error, reason}
    end
  end

  @doc """
  Run the simulation (start the clock ticking).
  """
  @spec run(String.t()) :: :ok | {:error, term()}
  def run(sim_id) do
    Clock.start_clock(sim_id)
  end

  @doc """
  Pause a running simulation.
  """
  @spec pause(String.t()) :: :ok
  def pause(sim_id) do
    Clock.pause(sim_id)
    EventBus.broadcast_lifecycle(sim_id, :paused)
    :ok
  end

  @doc """
  Resume a paused simulation.
  """
  @spec resume(String.t()) :: :ok | {:error, term()}
  def resume(sim_id) do
    Clock.start_clock(sim_id)
    EventBus.broadcast_lifecycle(sim_id, :resumed)
    :ok
  end

  @doc """
  Get the current status of a simulation.
  """
  @spec status(String.t()) :: map()
  def status(sim_id) do
    clock_status = Clock.status(sim_id)
    world_snapshot = World.snapshot(sim_id)
    agent_count = SimRegistry.count_agents(sim_id)

    %{
      sim_id: sim_id,
      clock: clock_status,
      world: world_snapshot,
      agent_count: agent_count
    }
  end

  @doc """
  Mark a simulation as completed and broadcast the lifecycle event.
  """
  @spec complete(String.t()) :: :ok
  def complete(sim_id) do
    EventBus.broadcast_lifecycle(sim_id, :completed)
    :ok
  end

  # --- Private ---

  defp start_world(sim_id, config, opts) do
    world_opts = [
      sim_id: sim_id,
      config: %{
        event_frequency: config.event_frequency,
        crisis_probability: config.crisis_probability,
        market_volatility: config.market_volatility
      },
      rng_seed: config.rng_seed,
      initial_entities: Keyword.get(opts, :initial_entities, []),
      initial_relationships: Keyword.get(opts, :initial_relationships, [])
    ]

    case World.start_link(world_opts) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, {:world_start_failed, reason}}
    end
  end

  defp spawn_agents(sim_id, personas, config, opts) do
    # Create a DynamicSupervisor for this simulation's agents
    # Use the stdlib Registry module directly for :via registration
    sup_name = {:via, Registry, {HydraX.Simulation.Registry, {:agent_sup, sim_id}}}

    case DynamicSupervisor.start_link(strategy: :one_for_one, name: sup_name) do
      {:ok, sup_pid} ->
        Population.spawn_population(sup_pid, sim_id, personas,
          rng_seed: config.rng_seed,
          novelty_threshold: config.novelty_threshold,
          stakes_threshold: config.stakes_threshold,
          llm_request_callback: Keyword.get(opts, :llm_request_callback)
        )

      {:error, reason} ->
        {:error, {:agent_sup_start_failed, reason}}
    end
  end

  defp wrap_config_error({:ok, config}), do: {:ok, config}
  defp wrap_config_error({:error, reasons}), do: {:error, {:invalid_config, reasons}}

  defp start_clock(sim_id, config, opts) do
    clock_opts = [
      sim_id: sim_id,
      max_ticks: config.max_ticks,
      tick_interval_ms: config.tick_interval_ms,
      tick_callback: Keyword.get(opts, :tick_callback)
    ]

    case Clock.start_link(clock_opts) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, {:clock_start_failed, reason}}
    end
  end

  defp cleanup(sim_id) do
    # Best-effort cleanup of any started processes
    for key <- [:world, :clock, :agent_sup] do
      case SimRegistry.lookup_process(sim_id, key) do
        {:ok, pid} -> GenServer.stop(pid, :shutdown, 1_000)
        _ -> :ok
      end
    end

    :ok
  catch
    _, _ -> :ok
  end

  defp generate_sim_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
