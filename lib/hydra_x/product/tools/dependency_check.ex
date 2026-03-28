defmodule HydraX.Product.Tools.DependencyCheck do
  @behaviour HydraX.Tool

  alias HydraX.Product.Graph

  @impl true
  def name, do: "dependency_check"

  @impl true
  def description, do: "Check what depends on an architecture node"

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "dependency_check",
      description:
        "Given an architecture node ID, traces its dependencies and reports what would be affected by changes.",
      input_schema: %{
        type: "object",
        properties: %{
          node_id: %{type: "integer", description: "Architecture node ID to check"},
          node_type: %{
            type: "string",
            description: "Node type (default: architecture_node)"
          }
        },
        required: ["node_id"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params) do
      node_id = params[:node_id] || params["node_id"]
      node_type = params[:node_type] || params["node_type"] || "architecture_node"

      upstream = Graph.trace_upstream(project_id, node_type, node_id)
      downstream = Graph.trace_downstream(project_id, node_type, node_id)
      %{affected: affected, count: count} = Graph.impact_of_change(project_id, node_type, node_id)

      {:ok,
       %{
         dependencies: %{
           node_type: node_type,
           node_id: node_id,
           upstream_count: length(upstream),
           upstream: Enum.map(upstream, &Map.take(&1, [:node_type, :node_id, :edge_kind])),
           downstream_count: length(downstream),
           downstream: Enum.map(downstream, &Map.take(&1, [:node_type, :node_id, :edge_kind])),
           impact_count: count,
           affected: Enum.map(affected, fn {type, id, kind} -> %{type: type, id: id, kind: kind} end)
         }
       }}
    end
  end

  @impl true
  def result_summary(%{dependencies: d}),
    do: "#{d.upstream_count} upstream, #{d.downstream_count} downstream, #{d.impact_count} impacted"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp extract_project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end
      _ -> {:error, :product_project_context_required}
    end
  end
end
