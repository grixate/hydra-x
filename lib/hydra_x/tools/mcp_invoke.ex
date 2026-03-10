defmodule HydraX.Tools.MCPInvoke do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "mcp_invoke"

  @impl true
  def description, do: "Invoke an action on enabled MCP integrations for the current agent"

  @impl true
  def safety_classification, do: "integration_action"

  @impl true
  def tool_schema do
    %{
      name: "mcp_invoke",
      description:
        "Invoke an action on enabled MCP integrations for the current agent. Use this when you need a bound MCP server to perform a concrete action instead of only inspecting or probing it.",
      input_schema: %{
        type: "object",
        properties: %{
          action: %{
            type: "string",
            description: "Action name to invoke on the MCP server"
          },
          server: %{
            type: "string",
            description: "Optional MCP server name or slug filter"
          },
          params: %{
            type: "object",
            description: "JSON object payload for the MCP action"
          }
        },
        required: ["action"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    agent_id = params[:agent_id] || params["agent_id"]
    action = params[:action] || params["action"]
    server = params[:server] || params["server"]
    invoke_params = params[:params] || params["params"] || %{}

    with action when is_binary(action) and action != "" <- action,
         {:ok, result} <-
           HydraX.Runtime.invoke_agent_mcp(
             agent_id,
             action,
             invoke_params,
             server: server
           ) do
      {:ok, result}
    else
      nil -> {:error, :missing_action}
      "" -> {:error, :missing_action}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def result_summary(%{action: action, count: count}),
    do: "invoked #{action} on #{count} MCP bindings"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
