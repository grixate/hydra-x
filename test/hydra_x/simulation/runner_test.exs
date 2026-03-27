defmodule HydraX.Simulation.Engine.RunnerTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Config
  alias HydraX.Simulation.Agent.Persona
  alias HydraX.Simulation.Engine.Runner
  alias HydraX.Simulation.World.{World, Clock, EventBus}

  setup do
    ensure_registry_started()
    :ok
  end

  defp ensure_registry_started do
    case Registry.start_link(keys: :unique, name: HydraX.Simulation.Registry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  defp test_personas(count) do
    for i <- 1..count do
      archetype =
        Enum.at(
          [:cautious_cfo, :visionary_ceo, :pragmatic_ops_director, :aggressive_competitor],
          rem(i, 4)
        )

      persona = Persona.archetype(archetype)
      %{persona | name: "#{persona.name} #{i}"}
    end
  end

  describe "start/3" do
    test "starts world, clock, and agents" do
      config = %Config{
        max_ticks: 5,
        tick_interval_ms: 100,
        agent_count: 5,
        rng_seed: 42
      }

      personas = test_personas(5)
      {:ok, sim_id} = Runner.start(config, personas)

      # World should be running
      snapshot = World.snapshot(sim_id)
      assert snapshot.tick == 0

      # Clock should be paused (not started automatically)
      status = Clock.status(sim_id)
      assert status.status == :paused
      assert status.max_ticks == 5

      # Agents should be registered
      agent_count = HydraX.Simulation.Registry.count_agents(sim_id)
      assert agent_count == 5
    end

    test "validates config before starting" do
      config = %Config{max_ticks: -1}
      personas = test_personas(2)

      assert {:error, {:invalid_config, _}} = Runner.start(config, personas)
    end
  end

  describe "run/1 and lifecycle" do
    test "run starts the clock" do
      config = %Config{
        max_ticks: 3,
        tick_interval_ms: 5000,
        rng_seed: 42
      }

      personas = test_personas(3)
      {:ok, sim_id} = Runner.start(config, personas)

      # Subscribe to lifecycle events
      EventBus.subscribe(sim_id)

      assert :ok = Runner.run(sim_id)

      status = Clock.status(sim_id)
      assert status.status == :running
    end

    test "pause stops clock ticking" do
      config = %Config{
        max_ticks: 100,
        tick_interval_ms: 5000,
        rng_seed: 42
      }

      personas = test_personas(3)
      {:ok, sim_id} = Runner.start(config, personas)

      Runner.run(sim_id)
      Runner.pause(sim_id)

      status = Clock.status(sim_id)
      assert status.status == :paused
    end
  end

  describe "status/1" do
    test "returns comprehensive status" do
      config = %Config{max_ticks: 5, rng_seed: 42}
      personas = test_personas(3)
      {:ok, sim_id} = Runner.start(config, personas)

      status = Runner.status(sim_id)

      assert status.sim_id == sim_id
      assert status.agent_count == 3
      assert status.clock.status == :paused
      assert status.world.tick == 0
    end
  end
end
