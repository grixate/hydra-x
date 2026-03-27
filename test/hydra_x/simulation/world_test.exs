defmodule HydraX.Simulation.World.WorldTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.World.World

  setup do
    sim_id = "world_test_#{System.unique_integer([:positive])}"
    ensure_registry_started()

    {:ok, _pid} =
      World.start_link(
        sim_id: sim_id,
        rng_seed: 42,
        config: %{event_frequency: 0.8, crisis_probability: 0.1, market_volatility: 0.5}
      )

    %{sim_id: sim_id}
  end

  defp ensure_registry_started do
    case Registry.start_link(keys: :unique, name: HydraX.Simulation.Registry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "entity management" do
    test "put and get entity", %{sim_id: sim_id} do
      World.put_entity(sim_id, "company_a", :company, %{market_cap: 1_000_000})

      assert {:ok, {"company_a", :company, %{market_cap: 1_000_000}}} =
               World.get_entity(sim_id, "company_a")
    end

    test "list entities", %{sim_id: sim_id} do
      World.put_entity(sim_id, "co_a", :company, %{})
      World.put_entity(sim_id, "co_b", :company, %{})

      entities = World.list_entities(sim_id)
      assert length(entities) == 2
    end

    test "get nonexistent entity returns :error", %{sim_id: sim_id} do
      assert :error = World.get_entity(sim_id, "nonexistent")
    end
  end

  describe "relationship management" do
    test "put and query relationships", %{sim_id: sim_id} do
      World.put_relationship(sim_id, "co_a", "co_b", :competitor, 0.8)
      World.put_relationship(sim_id, "co_a", "co_c", :partner, 0.6)

      rels = World.relationships_from(sim_id, "co_a")
      assert length(rels) == 2
    end

    test "query by relationship type", %{sim_id: sim_id} do
      World.put_relationship(sim_id, "co_a", "co_b", :competitor, 0.8)
      World.put_relationship(sim_id, "co_a", "co_c", :partner, 0.6)

      competitors = World.relationships_of_type(sim_id, "co_a", :competitor)
      assert length(competitors) == 1
      assert [{"co_a", "co_b", :competitor, 0.8}] = competitors
    end
  end

  describe "tick management" do
    test "starts at tick 0", %{sim_id: sim_id} do
      assert World.current_tick(sim_id) == 0
    end

    test "advance_tick increments", %{sim_id: sim_id} do
      assert World.advance_tick(sim_id) == 1
      assert World.current_tick(sim_id) == 1
    end
  end

  describe "global state" do
    test "default global state has expected keys", %{sim_id: sim_id} do
      gs = World.global_state(sim_id)
      assert Map.has_key?(gs, :market_sentiment)
      assert Map.has_key?(gs, :market_tension)
    end

    test "update_global_state merges", %{sim_id: sim_id} do
      World.update_global_state(sim_id, %{market_sentiment: 0.8})
      gs = World.global_state(sim_id)
      assert gs.market_sentiment == 0.8
    end
  end

  describe "event generation" do
    test "generates events based on config", %{sim_id: sim_id} do
      events = World.generate_events(sim_id)
      # With event_frequency 0.8, we should usually get events
      assert is_list(events)
    end

    test "deterministic with same seed" do
      sim_a = "world_det_a_#{System.unique_integer([:positive])}"
      sim_b = "world_det_b_#{System.unique_integer([:positive])}"

      {:ok, _} =
        World.start_link(
          sim_id: sim_a,
          rng_seed: 99,
          config: %{event_frequency: 1.0, crisis_probability: 0.5, market_volatility: 0.5}
        )

      {:ok, _} =
        World.start_link(
          sim_id: sim_b,
          rng_seed: 99,
          config: %{event_frequency: 1.0, crisis_probability: 0.5, market_volatility: 0.5}
        )

      events_a = World.generate_events(sim_a)
      events_b = World.generate_events(sim_b)

      types_a = Enum.map(events_a, & &1.type)
      types_b = Enum.map(events_b, & &1.type)

      assert types_a == types_b
    end
  end

  describe "snapshot" do
    test "returns world summary", %{sim_id: sim_id} do
      World.put_entity(sim_id, "co_a", :company, %{})
      snapshot = World.snapshot(sim_id)

      assert snapshot.sim_id == sim_id
      assert snapshot.tick == 0
      assert snapshot.entity_count == 1
    end
  end

  describe "apply_actions" do
    test "aggressive actions increase market tension", %{sim_id: sim_id} do
      gs_before = World.global_state(sim_id)

      actions = [
        {"agent_1", %{type: :aggressive_response}},
        {"agent_2", %{type: :aggressive_response}}
      ]

      World.apply_actions(sim_id, actions)
      gs_after = World.global_state(sim_id)

      assert gs_after.market_tension > gs_before.market_tension
    end
  end
end
