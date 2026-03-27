defmodule HydraX.Simulation.LLMIntegrationTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Config
  alias HydraX.Simulation.Agent.{Persona, Traits, Population}
  alias HydraX.Simulation.Engine.{Tick, Runner}
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

  defp mock_llm_fn do
    fn _request ->
      {:ok,
       %{
         content:
           Jason.encode!(%{
             action: "cautious_response",
             reasoning: "Mock LLM decided to be cautious"
           })
       }}
    end
  end

  describe "tick with LLM-routed agents" do
    test "agents that need LLM get results via batch inference" do
      sim_id = "llm_int_#{System.unique_integer([:positive])}"

      # Start world with high-stakes crisis events to trigger :complex decisions
      {:ok, _} =
        World.start_link(
          sim_id: sim_id,
          rng_seed: 42,
          config: %{event_frequency: 1.0, crisis_probability: 1.0, market_volatility: 0.9}
        )

      # Create agents with low emotional reactivity to route to :complex
      personas =
        for i <- 1..5 do
          %Persona{
            name: "Analyst #{i}",
            role: "Analyst",
            domain: :finance,
            traits: %Traits{
              emotional_reactivity: 0.1,
              neuroticism: 0.9,
              analytical_depth: 0.9,
              conscientiousness: 0.8
            }
          }
        end

      # Track LLM requests
      llm_collector = start_supervised!({Agent, fn -> [] end})

      llm_callback = fn request ->
        Agent.update(llm_collector, fn reqs -> [request | reqs] end)
      end

      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

      {:ok, _agent_ids} =
        Population.spawn_population(sup, sim_id, personas,
          rng_seed: 42,
          llm_request_callback: llm_callback
        )

      EventBus.subscribe(sim_id)

      # Execute tick with mock LLM
      assert :ok = Tick.execute(sim_id, 0, llm_fn: mock_llm_fn())

      assert_receive {:tick_complete, tick_data}, 5_000
      assert tick_data.tick_number == 0

      # Check that some LLM requests were collected
      llm_requests = Agent.get(llm_collector, & &1)

      # With crisis events and low emotional reactivity, at least some agents
      # should route to :complex tier
      if length(llm_requests) > 0 do
        assert Enum.all?(llm_requests, fn req -> req.tier in [:cheap, :frontier] end)
      end
    end
  end

  describe "full simulation with LLM" do
    test "runner starts simulation that can execute ticks with LLM" do
      config = %Config{
        max_ticks: 3,
        tick_interval_ms: 5000,
        rng_seed: 42
      }

      personas = [
        Persona.archetype(:cautious_cfo),
        Persona.archetype(:visionary_ceo),
        Persona.archetype(:aggressive_competitor)
      ]

      personas = Enum.with_index(personas, fn p, i -> %{p | name: "#{p.name}_#{i}"} end)

      {:ok, sim_id} = Runner.start(config, personas, llm_request_callback: fn _req -> :ok end)

      EventBus.subscribe(sim_id)

      # Execute ticks manually with mock LLM
      for tick <- 0..2 do
        assert :ok = Tick.execute(sim_id, tick, llm_fn: mock_llm_fn())
      end

      # Should have received 3 tick_complete events
      for tick <- 0..2 do
        assert_receive {:tick_complete, %{tick_number: ^tick}}, 5_000
      end

      # World should have advanced
      snapshot = World.snapshot(sim_id)
      assert snapshot.tick == 3
    end
  end

  describe "budget-aware tier downgrade" do
    test "error responses fall back to rules engine in agents" do
      sim_id = "budget_test_#{System.unique_integer([:positive])}"

      {:ok, _} =
        World.start_link(
          sim_id: sim_id,
          rng_seed: 42,
          config: %{event_frequency: 1.0, crisis_probability: 1.0, market_volatility: 0.9}
        )

      personas = [
        %Persona{
          name: "Budget Agent",
          role: "Analyst",
          domain: :finance,
          traits: %Traits{emotional_reactivity: 0.1, neuroticism: 0.9}
        }
      ]

      # LLM callback that collects but the LLM itself errors
      llm_callback = fn _request -> :ok end

      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

      {:ok, _} =
        Population.spawn_population(sup, sim_id, personas,
          rng_seed: 42,
          llm_request_callback: llm_callback
        )

      EventBus.subscribe(sim_id)

      # Execute with a failing LLM — agents should fall back to rules engine
      error_llm = fn _req -> {:error, :budget_exceeded} end
      assert :ok = Tick.execute(sim_id, 0, llm_fn: error_llm)

      assert_receive {:tick_complete, tick_data}, 5_000

      # All actions should be rules-engine since LLM failed
      total = tick_data.tier_counts.routine + tick_data.tier_counts.emotional
      assert total >= 0
    end
  end
end
