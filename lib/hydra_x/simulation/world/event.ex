defmodule HydraX.Simulation.World.Event do
  @moduledoc """
  Event struct for simulation world events.

  Events are the primary communication mechanism in the simulation — the world
  generates them, and agents observe and react to them based on their personality
  traits and current state.
  """

  @type event_type ::
          :market_shift
          | :price_change
          | :demand_surge
          | :supply_disruption
          | :competitor_move
          | :new_entrant
          | :acquisition_announced
          | :product_launch
          | :budget_pressure
          | :talent_departure
          | :innovation_breakthrough
          | :quality_issue
          | :regulation_change
          | :media_coverage
          | :investor_sentiment
          | :partnership_offer
          | :pr_crisis
          | :security_breach
          | :lawsuit
          | :market_crash
          | :negotiation_request
          | :alliance_proposal
          | :public_statement
          | :strategic_pivot
          | :hiring_spree
          | :cost_cutting
          | :conflict_escalation
          | :merger_discussion
          | :joint_venture_offer

  @type t :: %__MODULE__{
          id: String.t(),
          type: event_type(),
          source: :world | {:agent, String.t()},
          target: nil | String.t() | {:agent, String.t()},
          target_agent_id: String.t() | nil,
          description: String.t(),
          properties: map(),
          stakes: float(),
          emotional_valence: :positive | :negative | :neutral,
          is_crisis?: boolean(),
          is_threat?: boolean(),
          is_provocation?: boolean(),
          is_opportunity?: boolean(),
          is_windfall?: boolean(),
          involves_own_domain?: boolean(),
          tick: non_neg_integer()
        }

  defstruct id: nil,
            type: :market_shift,
            source: :world,
            target: nil,
            target_agent_id: nil,
            description: "",
            properties: %{},
            stakes: 0.5,
            emotional_valence: :neutral,
            is_crisis?: false,
            is_threat?: false,
            is_provocation?: false,
            is_opportunity?: false,
            is_windfall?: false,
            involves_own_domain?: false,
            tick: 0

  @doc """
  Create a new event with a generated ID.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    id = Map.get(attrs, :id, generate_id())
    struct(__MODULE__, Map.put(attrs, :id, id))
  end

  @doc """
  Check if two event types are in the same category.
  """
  @spec similar_type?(event_type(), event_type()) :: boolean()
  def similar_type?(type_a, type_b) when type_a == type_b, do: true

  def similar_type?(type_a, type_b) do
    category(type_a) == category(type_b)
  end

  @doc """
  Returns the category of an event type.
  """
  @spec category(event_type()) :: atom()
  def category(type) do
    case type do
      t when t in [:market_shift, :price_change, :demand_surge, :supply_disruption] ->
        :market

      t when t in [:competitor_move, :new_entrant, :acquisition_announced, :product_launch] ->
        :competitive

      t
      when t in [:budget_pressure, :talent_departure, :innovation_breakthrough, :quality_issue] ->
        :internal

      t
      when t in [:regulation_change, :media_coverage, :investor_sentiment, :partnership_offer] ->
        :external

      t when t in [:pr_crisis, :security_breach, :lawsuit, :market_crash] ->
        :crisis

      t
      when t in [
             :negotiation_request,
             :alliance_proposal,
             :public_statement,
             :strategic_pivot,
             :hiring_spree,
             :cost_cutting,
             :conflict_escalation,
             :merger_discussion,
             :joint_venture_offer
           ] ->
        :agent_generated

      _ ->
        :unknown
    end
  end

  @doc """
  Personalize an event for a specific agent by setting involves_own_domain?.
  """
  @spec personalize(t(), atom() | nil) :: t()
  def personalize(%__MODULE__{} = event, agent_domain) do
    involves =
      case {event.type, agent_domain} do
        {t, :finance} when t in [:budget_pressure, :price_change, :market_crash] ->
          true

        {t, :operations} when t in [:supply_disruption, :quality_issue, :talent_departure] ->
          true

        {t, :leadership}
        when t in [:strategic_pivot, :acquisition_announced, :merger_discussion] ->
          true

        {t, :technology}
        when t in [:innovation_breakthrough, :security_breach, :product_launch] ->
          true

        {t, :marketing} when t in [:media_coverage, :pr_crisis, :public_statement] ->
          true

        _ ->
          false
      end

    %{event | involves_own_domain?: involves}
  end

  @negotiation_types [
    :negotiation_request,
    :alliance_proposal,
    :merger_discussion,
    :conflict_escalation,
    :joint_venture_offer
  ]

  @doc """
  Returns true if the event type requires a counterpart agent.
  """
  @spec requires_counterpart?(t()) :: boolean()
  def requires_counterpart?(%__MODULE__{type: type}), do: type in @negotiation_types

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
