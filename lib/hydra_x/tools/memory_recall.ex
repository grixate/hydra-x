defmodule HydraX.Tools.MemoryRecall do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "memory_recall"

  @impl true
  def description, do: "Search typed memory"

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
