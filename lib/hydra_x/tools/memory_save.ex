defmodule HydraX.Tools.MemorySave do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "memory_save"

  @impl true
  def description, do: "Persist a typed memory entry"

  @impl true
  def tool_schema do
    %{
      name: "memory_save",
      description:
        "Save a new typed memory entry. Use this when the user asks you to remember something, or when important information should be persisted for future conversations.",
      input_schema: %{
        type: "object",
        properties: %{
          content: %{type: "string", description: "The content to remember"},
          type: %{
            type: "string",
            enum: [
              "Fact",
              "Preference",
              "Decision",
              "Identity",
              "Event",
              "Observation",
              "Goal",
              "Todo"
            ],
            description: "The type of memory (default: Fact)"
          },
          importance: %{
            type: "number",
            description: "Importance score from 0.0 to 1.0 (default: 0.7)"
          }
        },
        required: ["content"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    attrs = %{
      agent_id: params.agent_id || params["agent_id"],
      conversation_id: params[:conversation_id] || params["conversation_id"],
      type: params[:type] || params["type"] || "Fact",
      content: params[:content] || params["content"],
      importance: params[:importance] || params["importance"] || 0.7,
      metadata: params[:metadata] || params["metadata"] || %{},
      last_seen_at: DateTime.utc_now()
    }

    case HydraX.Memory.create_memory(attrs) do
      {:ok, memory} ->
        {:ok, %{id: memory.id, type: memory.type, content: memory.content}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
