defmodule HydraX.Simulation.Seed.EntityExtractor do
  @moduledoc """
  Extract named entities and relationships from seed document chunks
  using a single LLM call.
  """

  @doc """
  Extract entities and relationships from document chunks.

  Returns {:ok, %{entities: [...], relationships: [...]}} or {:error, reason}.
  """
  @spec extract([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def extract(chunks, opts \\ []) do
    llm_fn = Keyword.get(opts, :llm_fn)
    prompt = build_extraction_prompt(chunks)

    messages = [
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]

    request = %{
      messages: messages,
      process_type: "simulation_seed",
      max_tokens: 2000
    }

    result =
      if llm_fn do
        llm_fn.(request)
      else
        HydraX.LLM.Router.complete(request)
      end

    case result do
      {:ok, response} ->
        parse_extraction_response(response)

      {:error, reason} ->
        {:error, {:extraction_failed, reason}}
    end
  end

  defp system_prompt do
    """
    You are an entity extraction system. Given document chunks, extract:
    1. Named entities (companies, people, markets, products, resources)
    2. Relationships between entities (competitor, partner, employee, supplier, etc.)

    Respond with a JSON object:
    {
      "entities": [
        {"id": "unique_id", "type": "company|person|market|product|resource", "name": "...", "properties": {}}
      ],
      "relationships": [
        {"from": "entity_id", "to": "entity_id", "type": "competitor|partner|supplier|employee|customer", "weight": 0.0-1.0}
      ]
    }

    Respond ONLY with the JSON object.
    """
  end

  defp build_extraction_prompt(chunks) do
    chunk_text =
      chunks
      |> Enum.take(20)
      |> Enum.map_join("\n---\n", fn chunk ->
        Map.get(chunk, :content, Map.get(chunk, "content", ""))
      end)

    "Extract entities and relationships from this document:\n\n#{chunk_text}"
  end

  defp parse_extraction_response(response) do
    content = response[:content] || response["content"] || ""

    case Jason.decode(content) do
      {:ok, %{"entities" => entities, "relationships" => relationships}} ->
        parsed_entities =
          Enum.map(entities, fn e ->
            {e["id"], String.to_atom(e["type"] || "company"), e["properties"] || %{}}
          end)

        parsed_rels =
          Enum.map(relationships, fn r ->
            {r["from"], r["to"], String.to_atom(r["type"] || "related"), r["weight"] || 0.5}
          end)

        {:ok, %{entities: parsed_entities, relationships: parsed_rels}}

      {:ok, _} ->
        {:ok, %{entities: [], relationships: []}}

      {:error, _} ->
        {:ok, %{entities: [], relationships: []}}
    end
  end
end
