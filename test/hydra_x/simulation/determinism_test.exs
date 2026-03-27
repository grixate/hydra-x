defmodule HydraX.Simulation.DeterminismTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Agent.{Persona, Population}
  alias HydraX.Simulation.Engine.Tick
  alias HydraX.Simulation.World.{World, EventBus}

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

  defp run_simulation(seed) do
    sim_id = "det_#{seed}_#{System.unique_integer([:positive])}"

    {:ok, _} =
      World.start_link(
        sim_id: sim_id,
        rng_seed: seed,
        config: %{event_frequency: 1.0, crisis_probability: 0.2, market_volatility: 0.5}
      )

    personas = [
      Persona.archetype(:cautious_cfo),
      Persona.archetype(:visionary_ceo),
      Persona.archetype(:aggressive_competitor)
    ]

    personas = Enum.with_index(personas, fn p, i -> %{p | name: "#{p.name}_#{i}"} end)

    sup =
      start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: :"det_sup_#{sim_id}"})

    {:ok, _} = Population.spawn_population(sup, sim_id, personas, rng_seed: seed)

    EventBus.subscribe(sim_id)

    # Run 5 ticks
    tick_results =
      for tick <- 0..4 do
        :ok = Tick.execute(sim_id, tick)

        receive do
          {:tick_complete, data} -> data.tier_counts
        after
          5_000 -> %{}
        end
      end

    # Collect final world state
    world_snapshot = World.snapshot(sim_id)

    {tick_results, world_snapshot}
  end

  describe "reproducibility" do
    test "same seed produces identical routine tier counts" do
      seed = 12345

      {results_a, snapshot_a} = run_simulation(seed)
      {results_b, snapshot_b} = run_simulation(seed)

      # Event generation should be identical
      assert snapshot_a.tick == snapshot_b.tick

      # Routine + emotional actions (deterministic path) should match
      for {tier_a, tier_b} <- Enum.zip(results_a, results_b) do
        assert tier_a.routine == tier_b.routine,
               "Routine mismatch: #{inspect(tier_a)} vs #{inspect(tier_b)}"

        assert tier_a.emotional == tier_b.emotional,
               "Emotional mismatch: #{inspect(tier_a)} vs #{inspect(tier_b)}"
      end
    end

    test "different seeds produce different event sequences" do
      {results_a, _} = run_simulation(111)
      {results_b, _} = run_simulation(999)

      # With very different seeds, at least some ticks should differ
      # (not guaranteed per-tick, but very unlikely to be all identical)
      all_same =
        Enum.zip(results_a, results_b)
        |> Enum.all?(fn {a, b} -> a == b end)

      refute all_same, "Different seeds should produce different results"
    end
  end
end
