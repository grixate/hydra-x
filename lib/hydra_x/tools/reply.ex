defmodule HydraX.Tools.Reply do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "reply"

  @impl true
  def description, do: "Formats a final assistant reply"

  @impl true
  def safety_classification, do: "reply"

  @impl true
  def tool_schema do
    %{
      name: "reply",
      description:
        "Format and send a final reply to the user. Use this tool when you want to compose a structured response.",
      input_schema: %{
        type: "object",
        properties: %{
          reply: %{type: "string", description: "The reply text to send to the user"}
        },
        required: ["reply"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    {:ok, %{reply: Map.get(params, :reply) || Map.get(params, "reply", "")}}
  end

  @impl true
  def result_summary(%{reply: reply}) when is_binary(reply),
    do: "reply #{String.slice(reply, 0, 80)}"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
