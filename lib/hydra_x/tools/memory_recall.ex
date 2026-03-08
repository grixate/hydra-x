defmodule HydraX.Tools.MemoryRecall do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "memory_recall"

  @impl true
  def description, do: "Search typed memory"

  @impl true
  def tool_schema do
    %{
      name: "memory_recall",
      description: "Search the agent's typed memory for relevant entries. Use this when the user asks you to recall, remember, or look up something from past conversations.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query to match against stored memories"},
          limit: %{type: "integer", description: "Maximum number of results to return (default: 5)"}
        },
        required: ["query"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    memories =
      HydraX.Memory.search(
        params[:agent_id] || params["agent_id"],
        params[:query] || params["query"] || "",
        params[:limit] || params["limit"] || 5
      )

    {:ok,
     %{
       results:
         Enum.map(memories, fn memory ->
           %{
             id: memory.id,
             type: memory.type,
             content: memory.content,
             importance: memory.importance
           }
         end)
     }}
  end
end
