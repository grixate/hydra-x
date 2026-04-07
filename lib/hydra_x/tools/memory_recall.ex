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
          },
          scope_kind: %{type: "string", description: "Optional scope kind to prioritize"},
          scope_key: %{type: "string", description: "Optional scope key to prioritize"},
          hall: %{type: "string", description: "Optional hall to prioritize"},
          topic_key: %{type: "string", description: "Optional topic key to prioritize"},
          as_of: %{
            type: "string",
            description: "Optional ISO datetime used for temporal truth filtering"
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
        params[:limit] || params["limit"] || 5,
        scope_kind: params[:scope_kind] || params["scope_kind"],
        scope_key: params[:scope_key] || params["scope_key"],
        hall: params[:hall] || params["hall"],
        topic_key: params[:topic_key] || params["topic_key"],
        as_of: params[:as_of] || params["as_of"],
        include_related: true
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
             source_section: get_in(memory.metadata || %{}, ["source_section"]),
             scope_kind: memory.scope_kind,
             scope_key: memory.scope_key,
             hall: memory.hall,
             topic_key: memory.topic_key,
             valid_from: memory.valid_from,
             valid_to: memory.valid_to,
             evidence: ranked[:evidence] || [],
             related: ranked[:related] || []
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
