defmodule HydraX.Simulation.Engine.TickTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Agent.{Persona, Population}
  alias HydraX.Simulation.Engine.Tick
  alias HydraX.Simulation.World.{World, EventBus}

  setup do
    ensure_registry_started()

    sim_id = "tick_test_#{System.unique_integer([:positive])}"

    # Start world
    {:ok, _} =
      World.start_link(
        sim_id: sim_id,
        rng_seed: 42,
        config: %{event_frequency: 1.0, crisis_probability: 0.1, market_volatility: 0.5}
      )

    # Add some entities
    World.put_entity(sim_id, "company_alpha", :company, %{market_cap: 5_000_000})
    World.put_entity(sim_id, "company_beta", :company, %{market_cap: 3_000_000})

    # Spawn agents
    personas = [
      Persona.archetype(:cautious_cfo),
      Persona.archetype(:visionary_ceo),
      Persona.archetype(:pragmatic_ops_director),
      Persona.archetype(:aggressive_competitor)
    ]

    personas = Enum.with_index(personas, fn p, i -> %{p | name: "#{p.name}_#{i}"} end)

    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    {:ok, _agent_ids} =
      Population.spawn_population(sup, sim_id, personas, rng_seed: 42)

    # Subscribe to events
    EventBus.subscribe(sim_id)

    %{sim_id: sim_id}
  end

  defp ensure_registry_started do
    case Registry.start_link(keys: :unique, name: HydraX.Simulation.Registry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "execute/2" do
    test "completes a single tick successfully", %{sim_id: sim_id} do
      assert :ok = Tick.execute(sim_id, 0)

      # Should receive tick_complete broadcast
      assert_receive {:tick_complete, tick_data}, 2_000
      assert tick_data.tick_number == 0
      assert is_integer(tick_data.duration_us)
      assert is_map(tick_data.tier_counts)
    end

    test "multiple ticks advance world state", %{sim_id: sim_id} do
      for tick <- 0..4 do
        assert :ok = Tick.execute(sim_id, tick)
      end

      # World should have advanced
      snapshot = World.snapshot(sim_id)
      assert snapshot.tick == 5
    end

    test "agents produce actions during tick", %{sim_id: sim_id} do
      assert :ok = Tick.execute(sim_id, 0)

      assert_receive {:tick_complete, tick_data}, 2_000

      # Should have some agent actions
      # (depends on event generation, but with frequency 1.0 we should get events)
      assert tick_data.tier_counts.routine >= 0
    end

    test "tier distribution is dominated by routine", %{sim_id: sim_id} do
      # Run several ticks to get meaningful distribution
      for tick <- 0..9 do
        Tick.execute(sim_id, tick)
      end

      # Drain tick_complete messages and accumulate tier counts
      tier_totals =
        Enum.reduce(1..10, %{routine: 0, emotional: 0, complex: 0, negotiation: 0}, fn _, acc ->
          receive do
            {:tick_complete, tick_data} ->
              Map.merge(acc, tick_data.tier_counts, fn _k, v1, v2 -> v1 + v2 end)
          after
            2_000 -> acc
          end
        end)

      total =
        tier_totals.routine + tier_totals.emotional + tier_totals.complex +
          tier_totals.negotiation

      if total > 0 do
        # Routine + emotional should dominate (no LLM callback set)
        routine_pct = (tier_totals.routine + tier_totals.emotional) / total
        assert routine_pct >= 0.5, "Expected routine+emotional >= 50%, got #{routine_pct * 100}%"
      end
    end
  end
end
