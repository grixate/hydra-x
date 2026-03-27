defmodule HydraX.Simulation.Agent.Action do
  @moduledoc """
  Action type definitions for simulated agents.

  Actions are the outputs of agent decision-making. Each action has a type,
  metadata about how it was decided (rules engine vs LLM), and properties
  relevant to world state updates.

  The action space is organized by event category (spec §4.2).
  Each action also carries a volatility score for world state impact.
  """

  # Threat responses
  @type action_type ::
          :aggressive_counter
          | :defensive_retreat
          | :seek_allies
          | :damage_control
          | :public_statement
          | :wait_and_observe
          # Opportunity responses
          | :capitalize_aggressively
          | :capitalize_cautiously
          | :seek_consensus
          | :share_benefit
          # Competitive responses
          | :competitive_undercut
          | :differentiate
          | :ignore
          | :innovate_response
          # Internal responses
          | :cost_cutting
          | :invest_more
          | :restructure
          | :hire_replacement
          | :defer_to_authority
          # External responses
          | :comply_proactively
          | :lobby_against
          | :seek_legal_counsel
          | :adapt_strategy
          # Negotiation responses
          | :accept
          | :counter_offer
          | :reject
          | :defer_decision
          # Neutral
          | :do_nothing
          | :seek_information

  @type event_category ::
          :threat | :opportunity | :competitive | :internal | :external | :negotiation | :neutral

  @type t :: %__MODULE__{
          type: action_type(),
          properties: map(),
          method: :rules_engine | :cheap_llm | :frontier_llm | :emotional,
          source_event_type: atom() | nil,
          decided_at: integer() | nil
        }

  defstruct type: :do_nothing,
            properties: %{},
            method: :rules_engine,
            source_event_type: nil,
            decided_at: nil

  @doc """
  Create a new action.
  """
  @spec new(action_type(), map()) :: t()
  def new(type, properties \\ %{}) do
    method = Map.get(properties, :method, :rules_engine)

    %__MODULE__{
      type: type,
      properties: Map.delete(properties, :method),
      method: method,
      source_event_type: Map.get(properties, :event_type),
      decided_at: System.monotonic_time(:microsecond)
    }
  end

  @doc """
  Classify an event type into an event category (spec §4.2).
  """
  @spec classify_event_category(atom()) :: event_category()
  def classify_event_category(event_type) do
    case event_type do
      t when t in [:pr_crisis, :security_breach, :lawsuit, :market_crash] ->
        :threat

      t when t in [:partnership_offer, :innovation_breakthrough, :demand_surge] ->
        :opportunity

      t when t in [:competitor_move, :new_entrant, :product_launch, :acquisition_announced] ->
        :competitive

      t when t in [:budget_pressure, :talent_departure, :quality_issue] ->
        :internal

      t
      when t in [
             :regulation_change,
             :media_coverage,
             :investor_sentiment,
             :market_shift,
             :price_change,
             :supply_disruption
           ] ->
        :external

      t
      when t in [
             :negotiation_request,
             :alliance_proposal,
             :merger_discussion,
             :conflict_escalation,
             :joint_venture_offer
           ] ->
        :negotiation

      _ ->
        :neutral
    end
  end

  @doc """
  Returns the available action types for a given event type (spec §4.2).
  """
  @spec available_for(atom()) :: [action_type()]
  def available_for(event_type) do
    case classify_event_category(event_type) do
      :threat ->
        [
          :aggressive_counter,
          :defensive_retreat,
          :seek_allies,
          :damage_control,
          :public_statement,
          :wait_and_observe
        ]

      :opportunity ->
        [
          :capitalize_aggressively,
          :capitalize_cautiously,
          :seek_consensus,
          :share_benefit,
          :public_statement,
          :wait_and_observe
        ]

      :competitive ->
        [
          :competitive_undercut,
          :differentiate,
          :seek_allies,
          :ignore,
          :public_statement,
          :innovate_response
        ]

      :internal ->
        [
          :cost_cutting,
          :invest_more,
          :restructure,
          :hire_replacement,
          :seek_consensus,
          :defer_to_authority
        ]

      :external ->
        [
          :comply_proactively,
          :lobby_against,
          :public_statement,
          :wait_and_observe,
          :seek_legal_counsel,
          :adapt_strategy
        ]

      :negotiation ->
        [:accept, :counter_offer, :reject, :defer_decision, :seek_consensus]

      :neutral ->
        [:wait_and_observe, :seek_information, :do_nothing]
    end
  end

  @passive_actions [:wait_and_observe, :do_nothing, :seek_information, :ignore]
  @cooperative_actions [
    :seek_consensus,
    :accept,
    :share_benefit,
    :seek_allies,
    :comply_proactively
  ]
  @hostile_actions [:aggressive_counter, :competitive_undercut, :reject, :lobby_against]
  @accepting_actions [:accept, :share_benefit, :comply_proactively]

  @doc "Returns true if the action is passive."
  def passive?(action_type), do: action_type in @passive_actions

  @doc "Returns true if the action is cooperative."
  def cooperative?(action_type), do: action_type in @cooperative_actions

  @doc "Returns true if the action is hostile."
  def hostile?(action_type), do: action_type in @hostile_actions

  @doc "Returns true if the action is accepting."
  def accepting?(action_type), do: action_type in @accepting_actions

  @doc """
  Volatility score for an action (0.0 to 1.0).
  High-volatility actions create more downstream events.
  """
  @spec volatility(action_type()) :: float()
  def volatility(action_type) do
    case action_type do
      t when t in [:aggressive_counter, :capitalize_aggressively, :competitive_undercut] -> 0.9
      t when t in [:public_statement, :lobby_against, :restructure] -> 0.7
      t when t in [:invest_more, :innovate_response, :differentiate, :reject] -> 0.6
      t when t in [:cost_cutting, :hire_replacement, :adapt_strategy, :counter_offer] -> 0.5
      t when t in [:seek_allies, :seek_consensus, :damage_control, :comply_proactively] -> 0.4
      t when t in [:defensive_retreat, :capitalize_cautiously, :share_benefit, :accept] -> 0.3
      t when t in [:defer_to_authority, :defer_decision, :seek_legal_counsel] -> 0.2
      t when t in [:wait_and_observe, :seek_information, :ignore, :do_nothing] -> 0.1
      _ -> 0.3
    end
  end

  @doc """
  Relationship update deltas for an action (spec §4.5).
  Returns {sentiment_delta, trust_delta}.
  """
  @spec relationship_delta(action_type()) :: {float(), float()}
  def relationship_delta(action_type) do
    case action_type do
      :accept -> {+0.15, +0.08}
      :seek_consensus -> {+0.10, +0.05}
      :share_benefit -> {+0.20, +0.10}
      :seek_allies -> {+0.08, +0.03}
      :comply_proactively -> {+0.05, +0.05}
      :counter_offer -> {-0.03, +0.02}
      :competitive_undercut -> {-0.20, -0.12}
      :aggressive_counter -> {-0.18, -0.10}
      :reject -> {-0.12, -0.08}
      :lobby_against -> {-0.15, -0.10}
      :ignore -> {-0.02, -0.01}
      _ -> {0.0, 0.0}
    end
  end

  @doc """
  Convert an LLM decision response into an Action struct.
  """
  @spec from_llm_decision(map(), HydraX.Simulation.Agent.Persona.t()) :: t()
  def from_llm_decision(decision, _persona) do
    type =
      case Map.get(decision, "action", Map.get(decision, :action, "do_nothing")) do
        action when is_binary(action) ->
          try do
            String.to_existing_atom(action)
          rescue
            ArgumentError -> :do_nothing
          end

        action when is_atom(action) ->
          action
      end

    properties = Map.get(decision, "reasoning", Map.get(decision, :reasoning, %{}))

    properties =
      if is_binary(properties),
        do: %{reasoning: properties},
        else: properties

    method =
      case Map.get(decision, "tier", Map.get(decision, :tier)) do
        "frontier" -> :frontier_llm
        :frontier -> :frontier_llm
        _ -> :cheap_llm
      end

    %__MODULE__{
      type: type,
      properties: properties,
      method: method,
      decided_at: System.monotonic_time(:microsecond)
    }
  end
end
