defmodule HydraX.Tools.MemoryRecall do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "memory_recall"

  @impl true
  def description, do: "Search typed memory"

  @impl true
  def safety_classification, do: "memory_read"

  @impl true
  def tool_schema do
    %{
      name: "memory_recall",
      description:
        "Search the agent's typed memory for relevant entries. Use this when the user asks you to recall, remember, or look up something from past conversations.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query to match against stored memories"},
          limit: %{
            type: "integer",
            description: "Maximum number of results to return (default: 5)"
          }
        },
        required: ["query"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    ranked_memories =
      HydraX.Memory.search_ranked(
        params[:agent_id] || params["agent_id"],
        params[:query] || params["query"] || "",
        params[:limit] || params["limit"] || 5
      )

    {:ok,
     %{
       results:
         Enum.map(ranked_memories, fn ranked ->
           memory = ranked.entry

           %{
             id: memory.id,
             type: memory.type,
             status: memory.status,
             content: memory.content,
             importance: memory.importance,
             score: ranked.score,
             vector_score: ranked[:vector_score],
             embedding_backend: get_in(memory.metadata || %{}, ["embedding_backend"]),
             embedding_model: get_in(memory.metadata || %{}, ["embedding_model"]),
             embedding_fallback_from: get_in(memory.metadata || %{}, ["embedding_fallback_from"]),
             reasons: ranked.reasons,
             score_breakdown: ranked[:score_breakdown] || %{},
             lexical_rank: ranked.lexical_rank,
             semantic_rank: ranked.semantic_rank,
             source_file: get_in(memory.metadata || %{}, ["source_file"]),
             source_section: get_in(memory.metadata || %{}, ["source_section"])
           }
         end)
     }}
  end

  @impl true
  def result_summary(%{results: results}), do: "recalled #{length(results)} memories"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
