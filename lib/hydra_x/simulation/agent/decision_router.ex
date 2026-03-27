defmodule HydraX.Simulation.Agent.DecisionRouter do
  @moduledoc """
  Four-tier decision complexity classifier (spec §5).

  The decision router is the budget gatekeeper — it classifies every agent
  decision into one of four tiers BEFORE any LLM call is made.

  Classification runs in order — first match wins:

  1. `:negotiation` — frontier LLM (event is negotiation type + has counterpart + not recently negotiated)
  2. `:complex` — cheap LLM (novel + high stakes + genuinely torn)
  3. `:emotional` — rules engine fast path (non-neutral + high ER + has emotional flag)
  4. `:routine` — full weight calculation (default)

  The "genuinely torn" heuristic (§5.2) is key: even novel high-stakes events
  stay in :routine if the personality produces a clear winner (margin > 15%).
  """

  alias HydraX.Simulation.Agent.{Persona, Traits, Action}
  alias HydraX.Simulation.World.Event

  @type tier :: :routine | :emotional | :complex | :negotiation

  @negotiation_event_types [
    :negotiation_request,
    :alliance_proposal,
    :merger_discussion,
    :conflict_escalation,
    :joint_venture_offer
  ]

  @doc """
  Classify a decision into a processing tier (spec §5.1).
  """
  @spec classify(Persona.t(), Event.t(), map()) :: tier()
  def classify(%Persona{} = persona, %Event{} = event, state) do
    cond do
      negotiation?(event, state) -> :negotiation
      complex?(persona, event, state) -> :complex
      emotional?(event, persona.traits) -> :emotional
      true -> :routine
    end
  end

  # ── §5.1 Tier: NEGOTIATION ──

  defp negotiation?(%Event{} = event, state) do
    event.type in @negotiation_event_types and
      event.target_agent_id != nil and
      not been_negotiating_recently?(state)
  end

  # ── §5.1 Tier: COMPLEX ──

  defp complex?(%Persona{} = persona, %Event{} = event, state) do
    is_novel?(event, state) and
      event.stakes > stakes_threshold(state) and
      genuinely_torn?(persona.traits, event)
  end

  @doc """
  Check if the agent is genuinely torn between top two actions (spec §5.2).
  Computes personality_base weights, sorts, and checks if margin <= 15%.
  """
  def genuinely_torn?(%Traits{} = traits, %Event{} = event) do
    actions = Action.available_for(event.type)

    weights =
      actions
      |> Enum.map(fn action -> {action, Traits.personality_base(action, traits)} end)
      |> Enum.sort_by(fn {_a, w} -> -w end)

    Traits.compute_margin(weights) <= 0.15
  end

  # ── §5.1 Tier: EMOTIONAL ──

  defp emotional?(%Event{} = event, %Traits{} = traits) do
    event.emotional_valence != :neutral and
      traits.emotional_reactivity > 0.5 and
      (event.is_threat? or event.is_provocation? or event.is_windfall?)
  end

  # ── Shared helpers ──

  defp is_novel?(%Event{} = event, state) do
    beliefs = Map.get(state, :beliefs, [])
    category = Action.classify_event_category(event.type)

    similar_count =
      Enum.count(beliefs, fn {tag, _value, _tick} -> tag == category end)

    similar_count < Map.get(state, :novelty_threshold, 2)
  end

  defp been_negotiating_recently?(state) do
    beliefs = Map.get(state, :beliefs, [])
    current_tick = Map.get(state, :current_tick, 0)

    Enum.any?(beliefs, fn
      {:negotiation_result, _value, tick} -> current_tick - tick <= 3
      _ -> false
    end)
  end

  defp stakes_threshold(state), do: Map.get(state, :stakes_threshold, 0.7)
end
