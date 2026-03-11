defmodule HydraX.Tools.MCPCatalog do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "mcp_catalog"

  @impl true
  def description, do: "List available actions on enabled MCP integrations for the current agent"

  @impl true
  def safety_classification, do: "integration_read"

  @impl true
  def tool_schema do
    %{
      name: "mcp_catalog",
      description:
        "List available actions on enabled MCP integrations for the current agent. Use this before invoking an MCP action when you need to discover what a binding supports.",
      input_schema: %{
        type: "object",
        properties: %{
          server: %{
            type: "string",
            description: "Optional MCP server name or slug filter"
          },
          refresh: %{
            type: "boolean",
            description:
              "Refresh the HTTP action catalog before returning results (default: true)"
          }
        }
      }
    }
  end

  @impl true
  def execute(params, _context) do
    agent_id = params[:agent_id] || params["agent_id"]
    server = params[:server] || params["server"]
    refresh = truthy?(params[:refresh] || params["refresh"], true)

    HydraX.Runtime.list_agent_mcp_actions(agent_id, server: server, refresh: refresh)
  end

  @impl true
  def result_summary(%{count: count}), do: "listed actions for #{count} MCP bindings"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp truthy?(nil, default), do: default
  defp truthy?(value, _default) when is_boolean(value), do: value
  defp truthy?(value, _default) when value in ["true", "1", 1], do: true
  defp truthy?(value, _default) when value in ["false", "0", 0], do: false
  defp truthy?(_value, default), do: default
end
