defmodule HydraX.Tools.MCPProbe do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "mcp_probe"

  @impl true
  def description, do: "Probe enabled MCP integrations for the current agent"

  @impl true
  def safety_classification, do: "integration_read"

  @impl true
  def tool_schema do
    %{
      name: "mcp_probe",
      description:
        "Run live health probes against the current agent's enabled MCP integrations. Use this when you need to verify whether an MCP server is currently reachable before relying on it.",
      input_schema: %{
        type: "object",
        properties: %{
          server: %{
            type: "string",
            description: "Optional MCP server name or slug to probe"
          }
        }
      }
    }
  end

  @impl true
  def execute(params, _context) do
    agent_id = params[:agent_id] || params["agent_id"]
    server_filter = normalize_filter(params[:server] || params["server"])

    results =
      HydraX.Runtime.list_agent_mcp_servers(agent_id)
      |> Enum.filter(&(&1.enabled && &1.mcp_server_config.enabled))
      |> Enum.filter(fn binding ->
        is_nil(server_filter) or matches_filter?(binding.mcp_server_config, server_filter)
      end)
      |> Enum.map(fn binding ->
        case HydraX.Runtime.test_mcp_server(binding.mcp_server_config) do
          {:ok, result} ->
            %{
              id: binding.id,
              server_id: binding.mcp_server_config.id,
              name: binding.mcp_server_config.name,
              transport: binding.mcp_server_config.transport,
              status: "ok",
              detail: result.detail
            }

          {:error, reason} ->
            %{
              id: binding.id,
              server_id: binding.mcp_server_config.id,
              name: binding.mcp_server_config.name,
              transport: binding.mcp_server_config.transport,
              status: "warn",
              detail: inspect(reason)
            }
        end
      end)

    {:ok,
     %{
       agent_id: agent_id,
       count: length(results),
       results: results
     }}
  end

  @impl true
  def result_summary(%{count: count}), do: "probed #{count} MCP bindings"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp normalize_filter(nil), do: nil
  defp normalize_filter(""), do: nil
  defp normalize_filter(value), do: value |> to_string() |> String.downcase()

  defp matches_filter?(config, filter) do
    [config.name, get_in(config.metadata || %{}, ["slug"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase(to_string(&1)))
    |> Enum.any?(&String.contains?(&1, filter))
  end
end
