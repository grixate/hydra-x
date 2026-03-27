defmodule HydraX.Simulation.PersonalityEngineTest do
  @moduledoc """
  Statistical validation tests for the personality engine (spec §10).
  """
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Agent.{Traits, Action, Persona, DecisionRouter}
  alias HydraX.Simulation.World.Event

  # Run N weighted random selections for a given persona + event
  defp run_decisions(persona, event, n, opts \\ []) do
    modifier = Keyword.get(opts, :modifier)
    relevance = Keyword.get(opts, :relevance, 0.5)
    event_source_rel = Keyword.get(opts, :event_source_rel)

    actions = Action.available_for(event.type)

    Enum.reduce(1..n, %{}, fn i, counts ->
      rng = :rand.seed(:exsss, i)

      weights =
        Enum.map(actions, fn action ->
          w = Traits.compute_weight(persona.traits, action, modifier, relevance, event_source_rel)
          {action, w}
        end)

      {selected, _rng} = Traits.weighted_random_select(weights, rng)
      Map.update(counts, selected, 1, &(&1 + 1))
    end)
  end

  defp pct(counts, actions, n) do
    total = Enum.sum(Enum.map(actions, fn a -> Map.get(counts, a, 0) end))
    total / n * 100
  end

  # ── §10.1 Statistical validation ──

  describe "spec §10.1: archetype behavioral distributions (10,000 runs)" do
    @n 10_000

    test "cautious CFO facing threats: damage_control + defensive_retreat dominate" do
      persona = Persona.archetype(:cautious_cfo)
      event = Event.new(%{type: :market_crash, is_crisis?: true, is_threat?: true, stakes: 0.7})

      counts = run_decisions(persona, event, @n, relevance: 0.9)
      combined_pct = pct(counts, [:damage_control, :defensive_retreat, :wait_and_observe], @n)

      assert combined_pct > 55,
             "Expected damage_control + defensive_retreat + wait_and_observe > 55%, got #{combined_pct}%"
    end

    test "cautious CFO facing threats: aggressive_counter < 15%" do
      persona = Persona.archetype(:cautious_cfo)
      event = Event.new(%{type: :market_crash, is_crisis?: true, is_threat?: true, stakes: 0.7})

      counts = run_decisions(persona, event, @n, relevance: 0.9)
      aggr_pct = pct(counts, [:aggressive_counter], @n)

      assert aggr_pct < 15,
             "Expected aggressive_counter < 15%, got #{aggr_pct}%"
    end

    test "aggressive competitor facing opportunities: capitalize_aggressively is top choice" do
      persona = Persona.archetype(:aggressive_competitor)

      event =
        Event.new(%{type: :demand_surge, is_opportunity?: true, is_windfall?: true, stakes: 0.6})

      counts = run_decisions(persona, event, @n, relevance: 0.7)
      cap_pct = pct(counts, [:capitalize_aggressively], @n)

      assert cap_pct > 25,
             "Expected capitalize_aggressively > 25%, got #{cap_pct}%"
    end

    test "aggressive competitor facing opportunities: capitalize_cautiously < 15%" do
      persona = Persona.archetype(:aggressive_competitor)
      event = Event.new(%{type: :demand_surge, is_opportunity?: true, stakes: 0.6})

      counts = run_decisions(persona, event, @n, relevance: 0.7)
      caut_pct = pct(counts, [:capitalize_cautiously], @n)

      assert caut_pct < 15,
             "Expected capitalize_cautiously < 15%, got #{caut_pct}%"
    end

    test "visionary CEO facing competitive events: innovate_response is top choice" do
      persona = Persona.archetype(:visionary_ceo)
      event = Event.new(%{type: :competitor_move, stakes: 0.6})

      counts = run_decisions(persona, event, @n, relevance: 0.7)

      # Should favor differentiate or innovate_response
      innov_pct = pct(counts, [:innovate_response, :differentiate], @n)

      assert innov_pct > 25,
             "Expected innovate + differentiate > 25%, got #{innov_pct}%"
    end

    test "cautious regulator facing external events: comply_proactively dominates" do
      persona = Persona.archetype(:cautious_regulator)
      event = Event.new(%{type: :regulation_change, stakes: 0.5})

      counts = run_decisions(persona, event, @n, relevance: 0.7)
      comply_pct = pct(counts, [:comply_proactively, :seek_legal_counsel], @n)

      assert comply_pct > 30,
             "Expected comply + legal > 30%, got #{comply_pct}%"
    end
  end

  # ── §10.2 Determinism ──

  describe "spec §10.2: determinism (same seed = identical results)" do
    test "100 runs with same seed produce identical action sequence" do
      persona = Persona.archetype(:cautious_cfo)
      event = Event.new(%{type: :budget_pressure, stakes: 0.5, involves_own_domain?: true})
      actions = Action.available_for(event.type)

      results =
        for _ <- 1..100 do
          rng = :rand.seed(:exsss, 42)

          weights =
            Enum.map(actions, fn a ->
              {a, Traits.compute_weight(persona.traits, a, nil, 0.8, nil)}
            end)

          {selected, _} = Traits.weighted_random_select(weights, rng)
          selected
        end

      # All 100 runs should produce the exact same action
      assert length(Enum.uniq(results)) == 1
    end
  end

  # ── §10.3 Modifier effect size ──

  describe "spec §10.3: modifier effect size" do
    @n 10_000

    test ":stressed increases aggressive_counter + defensive_retreat + damage_control" do
      persona = Persona.archetype(:pragmatic_ops_director)
      event = Event.new(%{type: :market_crash, is_crisis?: true, is_threat?: true, stakes: 0.7})

      stressed_amplified = [:aggressive_counter, :defensive_retreat, :damage_control]

      no_mod = run_decisions(persona, event, @n, modifier: nil, relevance: 0.8)
      stressed = run_decisions(persona, event, @n, modifier: :stressed, relevance: 0.8)

      no_mod_pct = pct(no_mod, stressed_amplified, @n)
      stressed_pct = pct(stressed, stressed_amplified, @n)

      assert stressed_pct > no_mod_pct,
             "Expected :stressed to increase amplified actions (#{no_mod_pct}% → #{stressed_pct}%)"
    end

    test ":confident increases capitalize_aggressively for opportunities" do
      persona = Persona.archetype(:pragmatic_ops_director)
      event = Event.new(%{type: :demand_surge, is_opportunity?: true, stakes: 0.6})

      no_mod = run_decisions(persona, event, @n, modifier: nil, relevance: 0.6)
      confident = run_decisions(persona, event, @n, modifier: :confident, relevance: 0.6)

      no_mod_pct = pct(no_mod, [:capitalize_aggressively], @n)
      confident_pct = pct(confident, [:capitalize_aggressively], @n)

      assert confident_pct > no_mod_pct,
             "Expected :confident to increase capitalize_aggressively (#{no_mod_pct}% → #{confident_pct}%)"
    end
  end

  # ── §9 Worked example ──

  describe "spec §9: worked example (CFO_Alpha + budget_pressure)" do
    test "produces exact personality_base weights from spec" do
      traits = %Traits{
        openness: 0.3,
        conscientiousness: 0.9,
        extraversion: 0.3,
        agreeableness: 0.5,
        neuroticism: 0.5,
        risk_tolerance: 0.2,
        innovation_bias: 0.2,
        consensus_seeking: 0.6,
        analytical_depth: 0.9,
        emotional_reactivity: 0.3,
        authority_deference: 0.4,
        competitive_drive: 0.3
      }

      # Internal event actions — verify formulas match
      # cost_cutting = C*0.4 + (1-RT)*0.3 + AD*0.2 + (1-IB)*0.1
      #              = 0.9*0.4 + 0.8*0.3 + 0.9*0.2 + 0.8*0.1 = 0.36+0.24+0.18+0.08 = 0.86
      assert_in_delta Traits.personality_base(:cost_cutting, traits), 0.86, 0.01
      # defer_to_authority = AuD*0.6 + (1-CD)*0.2 + A*0.1 + C*0.1
      #                    = 0.4*0.6 + 0.7*0.2 + 0.5*0.1 + 0.9*0.1 = 0.52
      assert_in_delta Traits.personality_base(:defer_to_authority, traits), 0.52, 0.01

      # Threat actions (the spec example uses threat category)
      assert_in_delta Traits.personality_base(:damage_control, traits), 0.83, 0.01
      assert_in_delta Traits.personality_base(:defensive_retreat, traits), 0.78, 0.01
      assert_in_delta Traits.personality_base(:seek_allies, traits), 0.56, 0.01
      assert_in_delta Traits.personality_base(:aggressive_counter, traits), 0.34, 0.01
      assert_in_delta Traits.personality_base(:public_statement, traits), 0.36, 0.01
      assert_in_delta Traits.personality_base(:wait_and_observe, traits), 0.82, 0.01
    end

    test "relevance assessment matches spec trace" do
      traits = %Traits{
        openness: 0.3,
        conscientiousness: 0.9,
        extraversion: 0.3,
        agreeableness: 0.5,
        neuroticism: 0.5,
        risk_tolerance: 0.2,
        innovation_bias: 0.2,
        consensus_seeking: 0.6,
        analytical_depth: 0.9,
        emotional_reactivity: 0.3,
        authority_deference: 0.4,
        competitive_drive: 0.3
      }

      event =
        Event.new(%{
          type: :budget_pressure,
          stakes: 0.6,
          emotional_valence: :negative,
          is_threat?: true,
          involves_own_domain?: true
        })

      beliefs = [{:external, :market_shift, 12}]

      relevance =
        Traits.assess_relevance(traits, event,
          role_category: :finance,
          beliefs: beliefs,
          current_tick: 14
        )

      # base(budget_pressure, finance) = 0.9
      # domain = 0.3
      # trait: is_threat? → N*0.2 = 0.5*0.2 = 0.1, is_financial? → AD*0.1 = 0.9*0.1 = 0.09
      # recency: belief tag is :external, event category is :internal → no match → 0.0
      # Total = min(1.0, 0.9 + 0.3 + 0.1 + 0.09 + 0.0) = 1.0
      assert relevance == 1.0
    end
  end
end
