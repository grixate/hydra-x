defmodule HydraX.Simulation.Engine.PromptBuilder do
  @moduledoc """
  Builds LLM prompts for simulation agent decisions.

  Constructs system and user messages for deliberation (cheap tier)
  and negotiation (frontier tier) scenarios.
  """

  alias HydraX.Simulation.Agent.Persona

  @doc """
  Build a list of messages for an LLM request based on the request context.
  """
  @spec build(map()) :: [map()]
  def build(request) do
    case request.tier do
      :cheap -> build_deliberation(request)
      :frontier -> build_negotiation(request)
      _ -> build_deliberation(request)
    end
  end

  @doc """
  Build a deliberation prompt for complex decisions (cheap LLM tier).
  """
  def build_deliberation(request) do
    persona = request.persona
    event = request.event
    beliefs = request[:beliefs] || MapSet.new()
    modifier = request[:modifier]

    system_msg = %{
      role: "system",
      content: deliberation_system_prompt(persona)
    }

    user_msg = %{
      role: "user",
      content: deliberation_user_prompt(event, beliefs, modifier)
    }

    [system_msg, user_msg]
  end

  @doc """
  Build a negotiation prompt for multi-agent interactions (frontier LLM tier).
  """
  def build_negotiation(request) do
    persona = request.persona
    event = request.event
    beliefs = request[:beliefs] || MapSet.new()
    relationships = request[:relationships] || %{}
    counterpart_id = request[:counterpart_id]
    modifier = request[:modifier]

    system_msg = %{
      role: "system",
      content: negotiation_system_prompt(persona)
    }

    user_msg = %{
      role: "user",
      content: negotiation_user_prompt(event, beliefs, relationships, counterpart_id, modifier)
    }

    [system_msg, user_msg]
  end

  # --- Private: Deliberation ---

  defp deliberation_system_prompt(%Persona{} = persona) do
    """
    You are #{persona.name}, a #{persona.role}.
    #{if persona.backstory != "", do: "Background: #{persona.backstory}", else: ""}

    You are participating in a business strategy simulation. You must decide how to respond to a situation.

    Your personality traits (0.0 = low, 1.0 = high):
    #{format_traits(persona.traits)}

    Respond with a JSON object containing:
    - "action": one of #{inspect(action_options())}
    - "reasoning": a brief explanation (1-2 sentences)

    Respond ONLY with the JSON object, no other text.
    """
  end

  defp deliberation_user_prompt(event, beliefs, modifier) do
    parts = [
      "SITUATION: #{event.description || describe_event(event)}",
      "Event type: #{event.type}",
      "Stakes: #{event.stakes} (0=low, 1=critical)",
      "Emotional tone: #{event.emotional_valence}"
    ]

    parts =
      if MapSet.size(beliefs) > 0 do
        belief_str = beliefs |> MapSet.to_list() |> Enum.take(5) |> Enum.join(", ")
        parts ++ ["Your current beliefs: #{belief_str}"]
      else
        parts
      end

    parts =
      if modifier do
        parts ++ ["Your current emotional state: #{modifier}"]
      else
        parts
      end

    (parts ++ ["What action do you take?"])
    |> Enum.join("\n")
  end

  # --- Private: Negotiation ---

  defp negotiation_system_prompt(%Persona{} = persona) do
    """
    You are #{persona.name}, a #{persona.role}.
    #{if persona.backstory != "", do: "Background: #{persona.backstory}", else: ""}

    You are in a negotiation within a business strategy simulation. You must decide how to engage with another party.

    Your personality traits (0.0 = low, 1.0 = high):
    #{format_traits(persona.traits)}

    Consider the relationship dynamics, your strategic position, and the stakes involved.

    Respond with a JSON object containing:
    - "action": one of #{inspect(negotiation_action_options())}
    - "reasoning": your strategic rationale (2-3 sentences)
    - "stance": "cooperative" | "competitive" | "neutral"

    Respond ONLY with the JSON object, no other text.
    """
  end

  defp negotiation_user_prompt(event, beliefs, relationships, counterpart_id, modifier) do
    parts = [
      "NEGOTIATION CONTEXT: #{event.description || describe_event(event)}",
      "Event type: #{event.type}",
      "Stakes: #{event.stakes}"
    ]

    parts =
      if counterpart_id do
        rel_info =
          case Map.get(relationships, counterpart_id) do
            {sentiment, trust} -> "sentiment=#{sentiment}, trust=#{trust}"
            nil -> "no prior relationship"
          end

        parts ++ ["Counterpart: #{counterpart_id} (#{rel_info})"]
      else
        parts
      end

    parts =
      if MapSet.size(beliefs) > 0 do
        belief_str = beliefs |> MapSet.to_list() |> Enum.take(5) |> Enum.join(", ")
        parts ++ ["Your beliefs: #{belief_str}"]
      else
        parts
      end

    parts =
      if modifier do
        parts ++ ["Your emotional state: #{modifier}"]
      else
        parts
      end

    (parts ++ ["How do you engage in this negotiation?"])
    |> Enum.join("\n")
  end

  # --- Helpers ---

  defp format_traits(traits) do
    traits
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> "- #{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp describe_event(event) do
    type_str = event.type |> Atom.to_string() |> String.replace("_", " ")
    "A #{type_str} event has occurred (stakes: #{event.stakes})"
  end

  defp action_options do
    ~w(aggressive_response cautious_response innovative_proposal seek_consensus
       defer_to_authority wait_and_observe public_statement private_negotiation do_nothing)
  end

  defp negotiation_action_options do
    ~w(aggressive_response cautious_response seek_consensus private_negotiation
       defer_to_authority innovative_proposal do_nothing)
  end
end
