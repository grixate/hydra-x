defmodule HydraX.Tools.MCPInspect do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "mcp_inspect"

  @impl true
  def description, do: "Inspect enabled MCP integrations for the current agent"

  @impl true
  def safety_classification, do: "integration_read"

  @impl true
  def tool_schema do
    %{
      name: "mcp_inspect",
      description:
        "Inspect the current agent's MCP integrations and their health. Use this when you need to know which MCP servers are enabled or whether they are healthy before relying on them.",
      input_schema: %{
        type: "object",
        properties: %{
          only_enabled: %{
            type: "boolean",
            description: "Only include enabled MCP bindings (default: true)"
          },
          only_healthy: %{
            type: "boolean",
            description: "Only include healthy MCP bindings (default: false)"
          }
        }
      }
    }
  end

  @impl true
  def execute(params, _context) do
    agent_id = params[:agent_id] || params["agent_id"]
    only_enabled = truthy?(params[:only_enabled] || params["only_enabled"], true)
    only_healthy = truthy?(params[:only_healthy] || params["only_healthy"], false)

    status = HydraX.Runtime.agent_mcp_statuses(agent_id)

    bindings =
      status.bindings
      |> Enum.filter(fn binding -> not only_enabled or binding.enabled end)
      |> Enum.filter(fn binding -> not only_healthy or binding.status == :ok end)
      |> Enum.map(fn binding ->
        %{
          id: binding.id,
          server_id: binding.server_id,
          name: binding.server_name,
          transport: binding.transport,
          enabled: binding.enabled,
          server_enabled: binding.server_enabled,
          status: Atom.to_string(binding.status),
          detail: binding.detail
        }
      end)

    {:ok,
     %{
       agent_id: status.agent_id,
       agent_slug: status.agent_slug,
       total_bindings: status.total_bindings,
       enabled_bindings: status.enabled_bindings,
       healthy_bindings: status.healthy_bindings,
       bindings: bindings
     }}
  end

  @impl true
  def result_summary(%{bindings: bindings}), do: "inspected #{length(bindings)} MCP bindings"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp truthy?(nil, default), do: default
  defp truthy?(value, _default) when is_boolean(value), do: value
  defp truthy?(value, _default) when value in ["true", "1", 1], do: true
  defp truthy?(value, _default) when value in ["false", "0", 0], do: false
  defp truthy?(_value, default), do: default
end
