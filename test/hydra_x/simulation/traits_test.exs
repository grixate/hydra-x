defmodule HydraX.Simulation.Agent.TraitsTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Agent.{Traits, Persona}
  alias HydraX.Simulation.World.Event

  describe "assess_relevance/3" do
    test "CFO role + budget_pressure = high relevance" do
      traits = Persona.archetype(:cautious_cfo).traits
      event = Event.new(%{type: :budget_pressure, involves_own_domain?: true})

      relevance = Traits.assess_relevance(traits, event, role_category: :finance)
      # base 0.9 + domain 0.3 = 1.0 (clamped)
      assert relevance >= 0.9
    end

    test "crisis events boost relevance via neuroticism" do
      high_n = %Traits{neuroticism: 0.9}
      low_n = %Traits{neuroticism: 0.1}
      # Use a mid-range base relevance event so the boost is visible
      event = Event.new(%{type: :regulation_change, is_crisis?: true})

      high_rel = Traits.assess_relevance(high_n, event, role_category: :operations)
      low_rel = Traits.assess_relevance(low_n, event, role_category: :operations)

      assert high_rel > low_rel
    end

    test "own-domain events boost relevance by 0.3" do
      traits = %Traits{}
      event = Event.new(%{type: :market_shift, involves_own_domain?: true})

      with_domain = Traits.assess_relevance(traits, event, role_category: :c_suite)

      without =
        Traits.assess_relevance(traits, %{event | involves_own_domain?: false},
          role_category: :c_suite
        )

      assert_in_delta with_domain - without, 0.3, 0.01
    end

    test "recency boost adds 0.1 when belief matches" do
      traits = %Traits{}
      # Use a lower base so the boost is visible (not clamped at 1.0)
      event = Event.new(%{type: :regulation_change})

      no_beliefs = Traits.assess_relevance(traits, event, role_category: :operations, beliefs: [])

      with_beliefs =
        Traits.assess_relevance(traits, event,
          role_category: :operations,
          beliefs: [{:external, :regulation_change, 0}],
          current_tick: 5
        )

      assert_in_delta with_beliefs - no_beliefs, 0.1, 0.01
    end
  end

  describe "personality_base/2" do
    test "cautious CFO strongly weights damage_control for threat events" do
      traits = Persona.archetype(:cautious_cfo).traits

      dc = Traits.personality_base(:damage_control, traits)
      ac = Traits.personality_base(:aggressive_counter, traits)

      assert dc > ac
    end

    test "aggressive competitor strongly weights competitive_undercut" do
      traits = Persona.archetype(:aggressive_competitor).traits

      cu = Traits.personality_base(:competitive_undercut, traits)
      ig = Traits.personality_base(:ignore, traits)

      assert cu > ig
    end

    test "spec worked example: CFO_Alpha budget_pressure weights" do
      # Spec §9: damage_control=0.83, defensive_retreat=0.78
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

      dc = Traits.personality_base(:damage_control, traits)
      dr = Traits.personality_base(:defensive_retreat, traits)

      assert_in_delta dc, 0.83, 0.01
      assert_in_delta dr, 0.78, 0.01
    end
  end

  describe "compute_weight/5" do
    test "modifier :stressed amplifies aggressive_counter" do
      traits = %Traits{competitive_drive: 0.5, agreeableness: 0.5}

      normal = Traits.compute_weight(traits, :aggressive_counter, nil, 0.5, nil)
      stressed = Traits.compute_weight(traits, :aggressive_counter, :stressed, 0.5, nil)

      assert stressed > normal
    end

    test "high relevance suppresses passive actions" do
      traits = %Traits{}

      low_rel = Traits.compute_weight(traits, :wait_and_observe, nil, 0.2, nil)
      high_rel = Traits.compute_weight(traits, :wait_and_observe, nil, 1.0, nil)

      assert low_rel > high_rel
    end

    test "positive relationship boosts cooperative actions" do
      traits = %Traits{consensus_seeking: 0.7, agreeableness: 0.7}
      good_rel = %{sentiment: 0.5, trust: 0.7}

      with_rel = Traits.compute_weight(traits, :seek_consensus, nil, 0.5, good_rel)
      without_rel = Traits.compute_weight(traits, :seek_consensus, nil, 0.5, nil)

      assert with_rel > without_rel
    end

    test "minimum weight is 0.01" do
      # Even with everything suppressed, weight never goes to zero
      traits = %Traits{
        competitive_drive: 0.0,
        agreeableness: 1.0,
        risk_tolerance: 0.0,
        extraversion: 0.0
      }

      bad_rel = %{sentiment: 0.5, trust: 0.8}

      w = Traits.compute_weight(traits, :aggressive_counter, :aligned, 0.2, bad_rel)
      assert w >= 0.01
    end
  end

  describe "emotional_response/4" do
    test "threat events produce defensive/aggressive/allies/damage_control" do
      traits = %Traits{
        risk_tolerance: 0.2,
        competitive_drive: 0.3,
        consensus_seeking: 0.8,
        conscientiousness: 0.9,
        analytical_depth: 0.7
      }

      event = Event.new(%{type: :security_breach, is_threat?: true})
      rng = :rand.seed(:exsss, 42)

      {action, _new_rng} = Traits.emotional_response(traits, event, nil, rng)
      assert action in [:defensive_retreat, :aggressive_counter, :seek_allies, :damage_control]
    end

    test "provocation events include seek_legal_counsel" do
      traits = %Traits{conscientiousness: 0.9, analytical_depth: 0.9, risk_tolerance: 0.1}
      event = Event.new(%{type: :competitor_move, is_provocation?: true})
      rng = :rand.seed(:exsss, 42)

      {action, _} = Traits.emotional_response(traits, event, nil, rng)
      assert action in [:aggressive_counter, :ignore, :public_statement, :seek_legal_counsel]
    end

    test "windfall events include invest_more" do
      traits = %Traits{innovation_bias: 0.8, risk_tolerance: 0.8, openness: 0.7}
      event = Event.new(%{type: :demand_surge, is_windfall?: true})
      rng = :rand.seed(:exsss, 42)

      {action, _} = Traits.emotional_response(traits, event, nil, rng)

      assert action in [
               :capitalize_aggressively,
               :capitalize_cautiously,
               :share_benefit,
               :invest_more
             ]
    end

    test "surprise events produce seek_information/wait/public_statement" do
      traits = %Traits{analytical_depth: 0.7}
      event = Event.new(%{type: :media_coverage, emotional_valence: :negative})
      rng = :rand.seed(:exsss, 42)

      {action, _} = Traits.emotional_response(traits, event, nil, rng)
      assert action in [:seek_information, :wait_and_observe, :public_statement]
    end

    test "deterministic with same RNG seed" do
      traits = %Traits{risk_tolerance: 0.5, competitive_drive: 0.5}
      event = Event.new(%{type: :lawsuit, is_threat?: true})

      results =
        for _ <- 1..10 do
          rng = :rand.seed(:exsss, 123)
          {action, _} = Traits.emotional_response(traits, event, nil, rng)
          action
        end

      assert length(Enum.uniq(results)) == 1
    end
  end

  describe "compute_margin/1" do
    test "decisive weights have high margin" do
      weights = [{:damage_control, 0.83}, {:defensive_retreat, 0.5}, {:aggressive_counter, 0.3}]
      margin = Traits.compute_margin(weights)
      assert margin > 0.15
    end

    test "close weights have low margin" do
      weights = [{:a, 0.50}, {:b, 0.48}, {:c, 0.3}]
      margin = Traits.compute_margin(weights)
      assert margin <= 0.15
    end
  end

  describe "apply_noise/2" do
    test "shifts trait values within ±0.08 range" do
      traits = %Traits{openness: 0.5, conscientiousness: 0.5}
      rng = :rand.seed(:exsss, 42)

      {noisy, _rng} = Traits.apply_noise(traits, rng)

      assert_in_delta noisy.openness, 0.5, 0.09
      assert_in_delta noisy.conscientiousness, 0.5, 0.09
    end

    test "clamps to [0.0, 1.0]" do
      traits = %Traits{risk_tolerance: 0.0, competitive_drive: 1.0}
      rng = :rand.seed(:exsss, 42)

      {noisy, _rng} = Traits.apply_noise(traits, rng)

      assert noisy.risk_tolerance >= 0.0
      assert noisy.competitive_drive <= 1.0
    end
  end

  describe "weighted_random_select/2" do
    test "returns valid option" do
      options = [{:a, 1.0}, {:b, 2.0}, {:c, 3.0}]
      rng = :rand.seed(:exsss, 42)

      {selected, _new_rng} = Traits.weighted_random_select(options, rng)
      assert selected in [:a, :b, :c]
    end

    test "higher weights are selected more often" do
      options = [{:rare, 0.01}, {:common, 10.0}]

      counts =
        Enum.reduce(1..1000, %{rare: 0, common: 0}, fn i, acc ->
          rng = :rand.seed(:exsss, i)
          {selected, _} = Traits.weighted_random_select(options, rng)
          Map.update!(acc, selected, &(&1 + 1))
        end)

      assert counts.common > counts.rare * 5
    end
  end
end
