defmodule HydraX.Simulation.Seed.PersonaGenerator do
  @moduledoc """
  Generate simulation agent personas from extracted entities using a single LLM call.
  """

  alias HydraX.Simulation.Agent.{Persona, Traits}

  @doc """
  Generate personas based on extracted entity data.

  Returns {:ok, [%Persona{}]} or {:error, reason}.
  """
  @spec generate(map(), pos_integer(), keyword()) :: {:ok, [Persona.t()]} | {:error, term()}
  def generate(extracted, count, opts \\ []) do
    llm_fn = Keyword.get(opts, :llm_fn)
    prompt = build_generation_prompt(extracted, count)

    messages = [
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]

    request = %{
      messages: messages,
      process_type: "simulation_seed",
      max_tokens: 3000
    }

    result =
      if llm_fn do
        llm_fn.(request)
      else
        HydraX.LLM.Router.complete(request)
      end

    case result do
      {:ok, response} ->
        parse_persona_response(response, count)

      {:error, _reason} ->
        # Fall back to archetype-based generation
        {:ok, fallback_personas(count)}
    end
  end

  defp system_prompt do
    """
    You are a persona generation system for business strategy simulations.
    Generate diverse agent personas with distinct personality traits.

    Each persona should have:
    - name: A realistic name
    - role: Their organizational role
    - backstory: 1-2 sentence background
    - domain: one of "finance", "operations", "leadership", "technology", "marketing"
    - traits: Big Five + domain traits, each 0.0-1.0:
      openness, conscientiousness, extraversion, agreeableness, neuroticism,
      risk_tolerance, innovation_bias, consensus_seeking, analytical_depth,
      emotional_reactivity, authority_deference, competitive_drive

    Respond with a JSON object: {"personas": [...]}
    Respond ONLY with the JSON object.
    """
  end

  defp build_generation_prompt(extracted, count) do
    entity_summary =
      extracted.entities
      |> Enum.take(10)
      |> Enum.map_join(", ", fn {id, type, _props} -> "#{id} (#{type})" end)

    """
    Based on these entities: #{entity_summary}

    Generate #{count} diverse personas for a business strategy simulation.
    Include a mix of roles: executives, analysts, competitors, regulators.
    Ensure personality diversity — don't make everyone cautious or aggressive.
    """
  end

  defp parse_persona_response(response, target_count) do
    content = response[:content] || response["content"] || ""

    case Jason.decode(content) do
      {:ok, %{"personas" => persona_list}} when is_list(persona_list) ->
        personas =
          Enum.map(persona_list, fn p ->
            traits_map =
              (p["traits"] || %{})
              |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
              |> Map.new()

            domain =
              case p["domain"] do
                nil -> nil
                d when is_binary(d) -> String.to_atom(d)
                d when is_atom(d) -> d
              end

            %Persona{
              name: p["name"] || "Agent",
              role: p["role"] || "Participant",
              backstory: p["backstory"] || "",
              domain: domain,
              traits: struct(Traits, traits_map)
            }
          end)

        {:ok, personas}

      _ ->
        {:ok, fallback_personas(target_count)}
    end
  rescue
    _ -> {:ok, fallback_personas(target_count)}
  end

  defp fallback_personas(count) do
    archetypes = Persona.archetypes()

    for i <- 1..count do
      archetype = Enum.at(archetypes, rem(i - 1, length(archetypes)))
      base = Persona.archetype(archetype)
      %{base | name: "#{base.name} #{i}"}
    end
  end
end
