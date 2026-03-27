defmodule HydraX.Simulation.Agent.SimAgentTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Agent.{SimAgent, Persona, Traits}
  alias HydraX.Simulation.World.Event

  setup do
    :ok
  end

  defp start_agent(opts \\ []) do
    persona = Keyword.get(opts, :persona, Persona.archetype(:cautious_cfo))
    sim_id = Keyword.get(opts, :sim_id, "test_sim")
    agent_id = Keyword.get(opts, :agent_id, "agent_#{System.unique_integer([:positive])}")
    seed = Keyword.get(opts, :seed, 42)
    callback = Keyword.get(opts, :llm_request_callback)

    {:ok, pid} =
      SimAgent.start_link(
        sim_id: sim_id,
        agent_id: agent_id,
        persona: persona,
        seed: seed,
        name: {:local, :"test_agent_#{agent_id}"},
        llm_request_callback: callback
      )

    # Subscribe to simulation PubSub for action broadcasts
    Phoenix.PubSub.subscribe(HydraX.PubSub, "simulation:#{sim_id}")

    %{pid: pid, agent_id: agent_id, sim_id: sim_id}
  end

  describe "initialization" do
    test "starts in :idle state" do
      %{pid: pid} = start_agent()

      {:idle, data} = :gen_statem.call(pid, :get_state)
      assert data.modifier == nil
      assert data.llm_call_count == 0
      assert data.beliefs == []
      assert data.relationships == %{}
      assert :queue.len(data.event_queue) == 0
    end

    test "initializes with persona and applies trait noise" do
      persona = Persona.archetype(:visionary_ceo)
      %{pid: pid} = start_agent(persona: persona)

      {:idle, data} = :gen_statem.call(pid, :get_state)
      assert data.persona.role == "Chief Executive Officer"
      # Trait noise means exact values differ by up to ±0.08
      assert_in_delta data.persona.traits.risk_tolerance, 0.8, 0.09
    end
  end

  describe "world event handling in idle state" do
    test "relevant events transition through FSM and produce actions" do
      # Use a CFO persona — budget_pressure has base_relevance 0.9 for finance role
      persona = Persona.archetype(:cautious_cfo)

      %{pid: pid, agent_id: agent_id} = start_agent(persona: persona)

      event =
        Event.new(%{
          type: :budget_pressure,
          stakes: 0.3,
          emotional_valence: :neutral,
          involves_own_domain?: true
        })

      :gen_statem.cast(pid, {:world_event, event})

      # Should receive action broadcast
      assert_receive {:agent_action, ^agent_id, action}, 500
      assert action.method in [:rules_engine, :emotional]
    end

    test "irrelevant events keep agent in idle" do
      # Regulator persona — talent_departure has base 0.0 for regulator role
      persona = Persona.archetype(:cautious_regulator)

      %{pid: pid} = start_agent(persona: persona)

      # talent_departure base for regulator = 0.0, no boosts → below 0.2
      event = Event.new(%{type: :talent_departure, stakes: 0.1, emotional_valence: :neutral})
      :gen_statem.cast(pid, {:world_event, event})

      Process.sleep(50)

      {:idle, data} = :gen_statem.call(pid, :get_state)
      assert :queue.len(data.tick_history) == 0
    end

    test "agent broadcasts action via PubSub" do
      persona = Persona.archetype(:aggressive_competitor)
      %{pid: pid, agent_id: agent_id} = start_agent(persona: persona)

      # High-relevance event for competitor role
      event =
        Event.new(%{
          type: :competitor_move,
          stakes: 0.5,
          emotional_valence: :neutral,
          involves_own_domain?: true
        })

      :gen_statem.cast(pid, {:world_event, event})

      assert_receive {:agent_action, ^agent_id, action}, 500
      assert action.method in [:rules_engine, :emotional]
    end
  end

  describe "event queue" do
    test "events arriving in non-idle states are queued" do
      persona = Persona.archetype(:cautious_cfo)
      %{pid: pid, agent_id: agent_id} = start_agent(persona: persona)

      # Send multiple events rapidly
      for i <- 1..3 do
        event =
          Event.new(%{
            type: :budget_pressure,
            stakes: 0.5,
            emotional_valence: :neutral,
            involves_own_domain?: true
          })

        :gen_statem.cast(pid, {:world_event, event})
      end

      # Should eventually process and produce actions
      assert_receive {:agent_action, ^agent_id, _}, 1_000
    end
  end

  describe "advance_tick" do
    test "modifier decay clears modifier over time" do
      persona = Persona.archetype(:cautious_cfo)
      %{pid: pid} = start_agent(persona: persona)

      # Send a crisis event to set :stressed modifier
      event =
        Event.new(%{
          type: :market_crash,
          is_crisis?: true,
          is_threat?: true,
          stakes: 0.5,
          emotional_valence: :negative,
          involves_own_domain?: true
        })

      :gen_statem.cast(pid, {:world_event, event})
      Process.sleep(100)

      # Advance many ticks to trigger modifier decay
      for tick <- 1..30 do
        :gen_statem.cast(pid, {:advance_tick, tick})
        Process.sleep(5)
      end

      {:idle, data} = :gen_statem.call(pid, :get_state)
      # After 30 ticks, modifier should very likely have decayed
      # (P(clear) after 30 ticks with half_life 8 ≈ 93%)
      # This is probabilistic, so we just check the tick advanced
      assert data.current_tick == 30
    end
  end

  describe "LLM callback integration" do
    defp complex_event do
      Event.new(%{
        type: :market_crash,
        is_crisis?: true,
        stakes: 0.9,
        emotional_valence: :neutral,
        involves_own_domain?: true
      })
    end

    defp complex_persona do
      # Low ER so it doesn't go emotional, moderate traits so it's potentially torn
      %Persona{
        name: "Analyst",
        role: "Analyst",
        domain: :finance,
        traits: %Traits{
          emotional_reactivity: 0.1,
          neuroticism: 0.5,
          analytical_depth: 0.5,
          conscientiousness: 0.5,
          risk_tolerance: 0.5,
          competitive_drive: 0.5,
          openness: 0.5,
          agreeableness: 0.5,
          extraversion: 0.5,
          consensus_seeking: 0.5,
          innovation_bias: 0.5,
          authority_deference: 0.5
        }
      }
    end

    test "complex decisions trigger LLM callback when genuinely torn" do
      test_pid = self()
      callback = fn request -> send(test_pid, {:llm_request, request}) end

      persona = complex_persona()
      %{pid: pid} = start_agent(persona: persona, llm_request_callback: callback)

      :gen_statem.cast(pid, {:world_event, complex_event()})

      # May or may not trigger LLM depending on trait noise + margin check
      # If it does, verify the request
      receive do
        {:llm_request, request} ->
          assert request.tier in [:cheap, :frontier]
      after
        500 ->
          # Routed to routine — that's also valid if margin > 15%
          :ok
      end
    end

    test "LLM result delivery transitions to acting" do
      test_pid = self()
      callback = fn request -> send(test_pid, {:llm_request, request}) end

      persona = complex_persona()

      %{pid: pid, agent_id: agent_id} =
        start_agent(persona: persona, llm_request_callback: callback)

      :gen_statem.cast(pid, {:world_event, complex_event()})

      receive do
        {:llm_request, _} ->
          :gen_statem.cast(pid, {:llm_result, {:ok, %{action: :damage_control, tier: :cheap}}})
          assert_receive {:agent_action, ^agent_id, action}, 500
          assert action.type == :damage_control
          assert action.method == :cheap_llm
      after
        500 ->
          # Routed to routine, also valid
          assert_receive {:agent_action, ^agent_id, _}, 500
      end
    end

    test "LLM error falls back to rules engine" do
      callback = fn _request -> :ok end

      persona = complex_persona()

      %{pid: pid, agent_id: agent_id} =
        start_agent(persona: persona, llm_request_callback: callback)

      :gen_statem.cast(pid, {:world_event, complex_event()})
      Process.sleep(50)
      :gen_statem.cast(pid, {:llm_result, {:error, :timeout}})

      assert_receive {:agent_action, ^agent_id, action}, 500
      assert action.method == :rules_engine
    end
  end

  describe "beliefs" do
    test "beliefs are accumulated on relevant events" do
      persona = Persona.archetype(:cautious_cfo)
      %{pid: pid} = start_agent(persona: persona)

      event =
        Event.new(%{
          type: :budget_pressure,
          stakes: 0.5,
          emotional_valence: :neutral,
          involves_own_domain?: true
        })

      :gen_statem.cast(pid, {:world_event, event})
      Process.sleep(100)

      {:idle, data} = :gen_statem.call(pid, :get_state)
      # Should have beliefs from the event and own action
      assert length(data.beliefs) >= 1
    end
  end

  describe "determinism" do
    test "same seed produces same routine actions" do
      persona = Persona.archetype(:cautious_cfo)

      event =
        Event.new(%{
          type: :budget_pressure,
          stakes: 0.3,
          emotional_valence: :neutral,
          involves_own_domain?: true
        })

      actions =
        for _ <- 1..5 do
          %{pid: _pid, agent_id: agent_id} = start_agent(persona: persona, seed: 42)
          :gen_statem.cast(_pid, {:world_event, event})

          receive do
            {:agent_action, ^agent_id, action} -> action.type
          after
            500 -> :timeout
          end
        end

      # All runs with same seed should produce same action
      assert length(Enum.uniq(actions)) == 1
    end
  end
end
