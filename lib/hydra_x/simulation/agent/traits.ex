defmodule HydraX.Simulation.Agent.Traits do
  @moduledoc """
  Personality trait system based on Big Five + domain-specific dimensions.

  Implements the deterministic decision engine from the Personality Engine Spec.
  Converts personality dimensions into concrete behavioral weights for the
  rules engine. This is the core of the ~95% LLM cost reduction.

  ## Key formulas (spec §4)

  - `assess_relevance/3` — Four-component relevance score (§4.1)
  - `compute_weight/5` — Four-factor multiplicative action weight (§4.3)
  - `emotional_response/4` — Emotional response table (§4.4)
  - `personality_base/2` — Trait-to-weight mapping for 30 actions (§4.3.1)
  """

  alias HydraX.Simulation.Agent.Action
  alias HydraX.Simulation.World.Event

  @type t :: %__MODULE__{
          openness: float(),
          conscientiousness: float(),
          extraversion: float(),
          agreeableness: float(),
          neuroticism: float(),
          risk_tolerance: float(),
          innovation_bias: float(),
          consensus_seeking: float(),
          analytical_depth: float(),
          emotional_reactivity: float(),
          authority_deference: float(),
          competitive_drive: float()
        }

  defstruct openness: 0.5,
            conscientiousness: 0.5,
            extraversion: 0.5,
            agreeableness: 0.5,
            neuroticism: 0.5,
            risk_tolerance: 0.5,
            innovation_bias: 0.5,
            consensus_seeking: 0.5,
            analytical_depth: 0.5,
            emotional_reactivity: 0.5,
            authority_deference: 0.5,
            competitive_drive: 0.5

  # ── §2.3 Trait noise ──

  @doc """
  Apply ±0.08 uniform noise to all traits for spawn-time individuation.
  """
  @spec apply_noise(t(), :rand.state()) :: {t(), :rand.state()}
  def apply_noise(%__MODULE__{} = traits, rng) do
    fields = [
      :openness,
      :conscientiousness,
      :extraversion,
      :agreeableness,
      :neuroticism,
      :risk_tolerance,
      :innovation_bias,
      :consensus_seeking,
      :analytical_depth,
      :emotional_reactivity,
      :authority_deference,
      :competitive_drive
    ]

    {noisy_map, rng} =
      Enum.reduce(fields, {Map.from_struct(traits), rng}, fn field, {map, rng} ->
        {roll, rng} = :rand.uniform_s(rng)
        # uniform in [-0.08, +0.08]
        noise = (roll - 0.5) * 0.16
        value = map[field]
        clamped = max(0.0, min(1.0, value + noise))
        {Map.put(map, field, Float.round(clamped, 4)), rng}
      end)

    {struct(__MODULE__, noisy_map), rng}
  end

  # ── §4.1 Relevance assessment ──

  @base_relevance_table %{
    # {event_type, role_category} => base_relevance
    {:market_shift, :c_suite} => 0.6,
    {:market_shift, :operations} => 0.3,
    {:market_shift, :finance} => 0.8,
    {:market_shift, :external_competitor} => 0.5,
    {:market_shift, :regulator} => 0.2,
    {:competitor_move, :c_suite} => 0.7,
    {:competitor_move, :operations} => 0.3,
    {:competitor_move, :finance} => 0.4,
    {:competitor_move, :external_competitor} => 0.9,
    {:competitor_move, :regulator} => 0.1,
    {:budget_pressure, :c_suite} => 0.5,
    {:budget_pressure, :operations} => 0.6,
    {:budget_pressure, :finance} => 0.9,
    {:budget_pressure, :external_competitor} => 0.1,
    {:budget_pressure, :regulator} => 0.1,
    {:talent_departure, :c_suite} => 0.5,
    {:talent_departure, :operations} => 0.7,
    {:talent_departure, :finance} => 0.3,
    {:talent_departure, :external_competitor} => 0.2,
    {:talent_departure, :regulator} => 0.0,
    {:regulation_change, :c_suite} => 0.6,
    {:regulation_change, :operations} => 0.4,
    {:regulation_change, :finance} => 0.5,
    {:regulation_change, :external_competitor} => 0.4,
    {:regulation_change, :regulator} => 0.9,
    {:pr_crisis, :c_suite} => 0.9,
    {:pr_crisis, :operations} => 0.4,
    {:pr_crisis, :finance} => 0.3,
    {:pr_crisis, :external_competitor} => 0.6,
    {:pr_crisis, :regulator} => 0.5,
    {:product_launch, :c_suite} => 0.6,
    {:product_launch, :operations} => 0.7,
    {:product_launch, :finance} => 0.4,
    {:product_launch, :external_competitor} => 0.8,
    {:product_launch, :regulator} => 0.1,
    {:security_breach, :c_suite} => 0.8,
    {:security_breach, :operations} => 0.8,
    {:security_breach, :finance} => 0.5,
    {:security_breach, :external_competitor} => 0.3,
    {:security_breach, :regulator} => 0.7,
    {:innovation_breakthrough, :c_suite} => 0.6,
    {:innovation_breakthrough, :operations} => 0.5,
    {:innovation_breakthrough, :finance} => 0.3,
    {:innovation_breakthrough, :external_competitor} => 0.7,
    {:innovation_breakthrough, :regulator} => 0.1,
    {:partnership_offer, :c_suite} => 0.7,
    {:partnership_offer, :operations} => 0.4,
    {:partnership_offer, :finance} => 0.5,
    {:partnership_offer, :external_competitor} => 0.6,
    {:partnership_offer, :regulator} => 0.2,
    {:market_crash, :c_suite} => 0.8,
    {:market_crash, :operations} => 0.5,
    {:market_crash, :finance} => 1.0,
    {:market_crash, :external_competitor} => 0.7,
    {:market_crash, :regulator} => 0.6,
    {:lawsuit, :c_suite} => 0.7,
    {:lawsuit, :operations} => 0.3,
    {:lawsuit, :finance} => 0.6,
    {:lawsuit, :external_competitor} => 0.4,
    {:lawsuit, :regulator} => 0.8
  }

  @doc """
  Assess how relevant a world event is to this agent (spec §4.1).
  Four-component formula: base + domain + trait + recency.
  """
  @spec assess_relevance(t(), Event.t(), keyword()) :: float()
  def assess_relevance(%__MODULE__{} = traits, %Event{} = event, opts \\ []) do
    role_category = Keyword.get(opts, :role_category, :c_suite)
    beliefs = Keyword.get(opts, :beliefs, [])
    current_tick = Keyword.get(opts, :current_tick, 0)

    base = Map.get(@base_relevance_table, {event.type, role_category}, 0.3)
    domain = if event.involves_own_domain?, do: 0.3, else: 0.0

    trait =
      if(event.is_crisis?, do: traits.neuroticism * 0.2, else: 0.0) +
        if(event.is_opportunity?, do: traits.openness * 0.15, else: 0.0) +
        if(event.is_provocation?, do: traits.competitive_drive * 0.15, else: 0.0) +
        if(event_is_financial?(event), do: traits.analytical_depth * 0.1, else: 0.0)

    recency = recency_boost(event, beliefs, current_tick)

    min(1.0, max(0.0, base + domain + trait + recency))
  end

  defp event_is_financial?(%Event{type: t}) do
    t in [
      :market_shift,
      :price_change,
      :budget_pressure,
      :market_crash,
      :demand_surge,
      :supply_disruption
    ]
  end

  defp recency_boost(%Event{} = event, beliefs, current_tick) do
    category = Action.classify_event_category(event.type)

    has_recent =
      Enum.any?(beliefs, fn {tag, _value, tick} ->
        tag == category and current_tick - tick <= 10
      end)

    if has_recent, do: 0.1, else: 0.0
  end

  # ── §4.3 Trait-to-weight mapping ──

  @doc """
  Compute the final weight for an action using the four-factor multiplicative formula (spec §4.3).
  """
  @spec compute_weight(t(), atom(), atom() | nil, float(), map() | nil) :: float()
  def compute_weight(%__MODULE__{} = traits, action_type, modifier, relevance, event_source_rel) do
    base = personality_base(action_type, traits)
    mod = modifier_factor(action_type, modifier)
    urgency = relevance_urgency(action_type, relevance)
    rel = relationship_factor(action_type, event_source_rel)

    max(0.01, base * mod * urgency * rel)
  end

  @doc """
  Compatibility wrapper used by the simulation tests and rules engine.
  Accepts the older public action names and derives relevance from the event.
  """
  @spec action_weight(t(), atom(), Event.t(), atom() | nil) :: float()
  def action_weight(%__MODULE__{} = traits, action_type, %Event{} = event, modifier) do
    relevance = assess_relevance(traits, event)
    compute_weight(traits, canonical_action_type(action_type), modifier, relevance, nil)
  end

  @doc """
  Compute personality_base weight for an action (spec §4.3.1).
  Each formula sums to 1.0 in coefficient weights, output in [0.0, 1.0].
  """
  @spec personality_base(atom(), t()) :: float()
  def personality_base(action, %__MODULE__{} = t) do
    case action do
      :aggressive_counter ->
        t.competitive_drive * 0.4 + (1 - t.agreeableness) * 0.3 + t.risk_tolerance * 0.2 +
          t.extraversion * 0.1

      :defensive_retreat ->
        (1 - t.risk_tolerance) * 0.4 + t.conscientiousness * 0.3 + (1 - t.competitive_drive) * 0.2 +
          t.neuroticism * 0.1

      :seek_allies ->
        t.consensus_seeking * 0.4 + t.agreeableness * 0.3 + (1 - t.competitive_drive) * 0.2 +
          t.extraversion * 0.1

      :damage_control ->
        t.conscientiousness * 0.4 + t.analytical_depth * 0.3 + (1 - t.risk_tolerance) * 0.2 +
          t.authority_deference * 0.1

      :public_statement ->
        t.extraversion * 0.5 + t.competitive_drive * 0.2 + (1 - t.authority_deference) * 0.2 +
          t.openness * 0.1

      :wait_and_observe ->
        t.analytical_depth * 0.3 + t.conscientiousness * 0.3 + (1 - t.emotional_reactivity) * 0.2 +
          (1 - t.extraversion) * 0.2

      :capitalize_aggressively ->
        t.risk_tolerance * 0.4 + t.competitive_drive * 0.3 + t.openness * 0.2 +
          (1 - t.conscientiousness) * 0.1

      :capitalize_cautiously ->
        (1 - t.risk_tolerance) * 0.3 + t.conscientiousness * 0.3 + t.analytical_depth * 0.2 +
          t.consensus_seeking * 0.2

      :seek_consensus ->
        t.consensus_seeking * 0.5 + t.agreeableness * 0.3 + t.authority_deference * 0.1 +
          (1 - t.competitive_drive) * 0.1

      :share_benefit ->
        t.agreeableness * 0.5 + t.consensus_seeking * 0.2 + (1 - t.competitive_drive) * 0.2 +
          t.openness * 0.1

      :competitive_undercut ->
        t.competitive_drive * 0.5 + t.risk_tolerance * 0.2 + (1 - t.agreeableness) * 0.2 +
          t.extraversion * 0.1

      :differentiate ->
        t.innovation_bias * 0.4 + t.openness * 0.3 + t.analytical_depth * 0.2 +
          t.conscientiousness * 0.1

      :ignore ->
        (1 - t.neuroticism) * 0.3 + (1 - t.emotional_reactivity) * 0.3 + t.analytical_depth * 0.2 +
          (1 - t.extraversion) * 0.2

      :innovate_response ->
        t.innovation_bias * 0.5 + t.openness * 0.3 + t.risk_tolerance * 0.1 +
          (1 - t.authority_deference) * 0.1

      :cost_cutting ->
        t.conscientiousness * 0.4 + (1 - t.risk_tolerance) * 0.3 + t.analytical_depth * 0.2 +
          (1 - t.innovation_bias) * 0.1

      :invest_more ->
        t.risk_tolerance * 0.4 + t.innovation_bias * 0.3 + t.openness * 0.2 +
          (1 - t.conscientiousness) * 0.1

      :restructure ->
        t.analytical_depth * 0.3 + t.conscientiousness * 0.3 + t.competitive_drive * 0.2 +
          (1 - t.authority_deference) * 0.2

      :hire_replacement ->
        t.conscientiousness * 0.4 + (1 - t.risk_tolerance) * 0.2 + t.analytical_depth * 0.2 +
          t.authority_deference * 0.2

      :defer_to_authority ->
        t.authority_deference * 0.6 + (1 - t.competitive_drive) * 0.2 + t.agreeableness * 0.1 +
          t.conscientiousness * 0.1

      :comply_proactively ->
        t.conscientiousness * 0.4 + t.authority_deference * 0.3 + (1 - t.risk_tolerance) * 0.2 +
          t.agreeableness * 0.1

      :lobby_against ->
        t.competitive_drive * 0.3 + (1 - t.authority_deference) * 0.3 + t.extraversion * 0.2 +
          t.risk_tolerance * 0.2

      :adapt_strategy ->
        t.openness * 0.3 + t.analytical_depth * 0.3 + t.innovation_bias * 0.2 +
          t.conscientiousness * 0.2

      :do_nothing ->
        0.15

      :seek_information ->
        t.analytical_depth * 0.4 + t.conscientiousness * 0.3 + (1 - t.emotional_reactivity) * 0.2 +
          t.openness * 0.1

      :accept ->
        t.agreeableness * 0.4 + t.consensus_seeking * 0.3 + (1 - t.competitive_drive) * 0.2 +
          t.authority_deference * 0.1

      :counter_offer ->
        t.competitive_drive * 0.3 + t.analytical_depth * 0.3 + t.risk_tolerance * 0.2 +
          (1 - t.agreeableness) * 0.2

      :reject ->
        (1 - t.agreeableness) * 0.3 + t.competitive_drive * 0.3 + (1 - t.consensus_seeking) * 0.2 +
          (1 - t.authority_deference) * 0.2

      :defer_decision ->
        t.authority_deference * 0.4 + t.consensus_seeking * 0.3 + (1 - t.competitive_drive) * 0.2 +
          t.conscientiousness * 0.1

      :seek_legal_counsel ->
        t.conscientiousness * 0.3 + t.analytical_depth * 0.3 + (1 - t.risk_tolerance) * 0.2 +
          t.authority_deference * 0.2

      _ ->
        0.15
    end
  end

  # ── §4.3.2 Modifier factor ──

  @stressed_amplified [:aggressive_counter, :defensive_retreat, :damage_control, :cost_cutting]
  @stressed_suppressed [
    :wait_and_observe,
    :capitalize_aggressively,
    :invest_more,
    :do_nothing,
    :innovate_response
  ]
  @confident_amplified [
    :aggressive_counter,
    :capitalize_aggressively,
    :competitive_undercut,
    :public_statement,
    :invest_more,
    :reject
  ]
  @confident_suppressed [
    :defensive_retreat,
    :seek_allies,
    :defer_to_authority,
    :do_nothing,
    :wait_and_observe
  ]
  @uncertain_amplified [
    :wait_and_observe,
    :seek_information,
    :seek_consensus,
    :seek_legal_counsel,
    :defer_to_authority
  ]
  @uncertain_suppressed [
    :aggressive_counter,
    :capitalize_aggressively,
    :competitive_undercut,
    :reject,
    :public_statement
  ]
  @aligned_amplified [:seek_consensus, :accept, :share_benefit, :comply_proactively, :seek_allies]
  @aligned_suppressed [:competitive_undercut, :aggressive_counter, :reject, :lobby_against]

  defp modifier_factor(_action, nil), do: 1.0

  defp modifier_factor(action, :stressed) do
    cond do
      action in @stressed_amplified -> 1.5
      action in @stressed_suppressed -> 0.5
      true -> 1.0
    end
  end

  defp modifier_factor(action, :confident) do
    cond do
      action in @confident_amplified -> 1.5
      action in @confident_suppressed -> 0.5
      true -> 1.0
    end
  end

  defp modifier_factor(action, :uncertain) do
    cond do
      action in @uncertain_amplified -> 1.5
      action in @uncertain_suppressed -> 0.5
      true -> 1.0
    end
  end

  defp modifier_factor(action, :aligned) do
    cond do
      action in @aligned_amplified -> 1.5
      action in @aligned_suppressed -> 0.5
      true -> 1.0
    end
  end

  defp modifier_factor(_action, _), do: 1.0

  # ── §4.3.3 Relevance urgency ──

  defp relevance_urgency(action, relevance) do
    if Action.passive?(action) do
      1.0 - relevance * 0.5
    else
      0.7 + relevance * 0.3
    end
  end

  # ── §4.3.4 Relationship factor ──

  defp relationship_factor(_action, nil), do: 1.0

  defp relationship_factor(action, %{sentiment: sentiment, trust: trust}) do
    cooperative_factor =
      cond do
        sentiment > 0.3 and Action.cooperative?(action) -> 1.3
        sentiment > 0.3 and Action.hostile?(action) -> 0.6
        sentiment < -0.3 and Action.cooperative?(action) -> 0.6
        sentiment < -0.3 and Action.hostile?(action) -> 1.3
        true -> 1.0
      end

    trust_factor =
      if trust < 0.3 and Action.accepting?(action), do: 0.5, else: 1.0

    cooperative_factor * trust_factor
  end

  defp relationship_factor(_action, _), do: 1.0

  # ── §4.4 Emotional response table ──

  @doc """
  Generate an emotional response action deterministically (spec §4.4).
  Returns {action_type, new_rng_state}.
  """
  @spec emotional_response(t(), Event.t(), atom() | nil, :rand.state()) ::
          {atom(), :rand.state()}
  def emotional_response(%__MODULE__{} = t, %Event{} = event, _modifier, rng_state) do
    cond do
      neutral_event?(event) ->
        {:acknowledge, rng_state}

      true ->
        options =
          cond do
            event.is_threat? ->
              [
                {:defensive_retreat, (1 - t.risk_tolerance) * 0.6 + t.neuroticism * 0.2},
                {:aggressive_counter,
                 t.competitive_drive * 0.4 + t.emotional_reactivity * 0.3 + t.risk_tolerance * 0.2},
                {:seek_allies, t.consensus_seeking * 0.4 + t.agreeableness * 0.3},
                {:damage_control, t.conscientiousness * 0.5 + t.analytical_depth * 0.2}
              ]

            event.is_provocation? ->
              [
                {:aggressive_counter,
                 t.competitive_drive * 0.4 + t.emotional_reactivity * 0.4 +
                   (1 - t.agreeableness) * 0.2},
                {:ignore,
                 (1 - t.neuroticism) * 0.3 + (1 - t.emotional_reactivity) * 0.4 +
                   t.conscientiousness * 0.2},
                {:public_statement, t.extraversion * 0.4 + t.competitive_drive * 0.3},
                {:seek_legal_counsel,
                 t.conscientiousness * 0.3 + t.analytical_depth * 0.3 +
                   (1 - t.risk_tolerance) * 0.2}
              ]

            event.is_windfall? ->
              [
                {:capitalize_aggressively,
                 t.risk_tolerance * 0.5 + t.competitive_drive * 0.3 + t.openness * 0.2},
                {:capitalize_cautiously,
                 t.conscientiousness * 0.4 + (1 - t.risk_tolerance) * 0.3 +
                   t.analytical_depth * 0.2},
                {:share_benefit, t.agreeableness * 0.5 + t.consensus_seeking * 0.3},
                {:invest_more,
                 t.innovation_bias * 0.3 + t.risk_tolerance * 0.3 + t.openness * 0.2}
              ]

            true ->
              # Surprise events (non-neutral valence, no specific flag)
              [
                {:seek_information, t.analytical_depth * 0.4 + t.conscientiousness * 0.3},
                {:wait_and_observe,
                 (1 - t.emotional_reactivity) * 0.4 + t.conscientiousness * 0.3},
                {:public_statement, t.extraversion * 0.4 + t.emotional_reactivity * 0.3}
              ]
          end

        weighted_random_select(options, rng_state)
    end
  end

  # ── §5.2 Genuinely torn heuristic ──

  @doc """
  Compute the margin between the top two action weights.
  Returns the margin ratio (0.0 to 1.0). If <= 0.15, the agent is genuinely torn.
  """
  @spec compute_margin([{atom(), float()}]) :: float()
  def compute_margin(sorted_weights) do
    case sorted_weights do
      [{_, w1}, {_, w2} | _] when w1 > 0 -> (w1 - w2) / w1
      _ -> 1.0
    end
  end

  # ── Weighted random selection ──

  @doc """
  Select from weighted options using provided RNG state.
  Returns {selected_option, new_rng_state}.
  """
  @spec weighted_random_select([{atom(), float()}], :rand.state()) ::
          {atom(), :rand.state()}
  def weighted_random_select([], rng_state), do: {:do_nothing, rng_state}

  def weighted_random_select(weighted_options, rng_state) do
    total = Enum.reduce(weighted_options, 0.0, fn {_opt, w}, acc -> acc + w end)

    if total == 0.0 do
      {elem(hd(weighted_options), 0), rng_state}
    else
      {roll, new_rng} = :rand.uniform_s(rng_state)
      threshold = roll * total

      selected =
        Enum.reduce_while(weighted_options, 0.0, fn {opt, w}, acc ->
          new_acc = acc + w
          if new_acc >= threshold, do: {:halt, opt}, else: {:cont, new_acc}
        end)

      selected =
        case selected do
          f when is_float(f) -> elem(List.last(weighted_options), 0)
          atom -> atom
        end

      {selected, new_rng}
    end
  end

  defp canonical_action_type(:aggressive_response), do: :aggressive_counter
  defp canonical_action_type(:cautious_response), do: :wait_and_observe
  defp canonical_action_type(:acknowledge), do: :do_nothing
  defp canonical_action_type(action_type), do: action_type

  defp neutral_event?(%Event{} = event) do
    not event.is_threat? and
      not event.is_provocation? and
      not event.is_windfall? and
      not event.is_opportunity? and
      not event.is_crisis? and
      event.emotional_valence == :neutral
  end
end
