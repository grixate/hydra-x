defmodule HydraX.Product.Tools.TrailTrace do
  @behaviour HydraX.Tool

  alias HydraX.Product.Graph

  @impl true
  def name, do: "trail_trace"

  @impl true
  def description, do: "Trace the full upstream and downstream chain for a graph node"

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "trail_trace",
      description:
        "Given a node type and ID, returns the full upstream lineage ('why this exists') and downstream dependencies ('what depends on this') as formatted text.",
      input_schema: %{
        type: "object",
        properties: %{
          node_type: %{type: "string", description: "Type of the node to trace"},
          node_id: %{type: "integer", description: "ID of the node to trace"},
          max_depth: %{type: "integer", description: "Maximum traversal depth (default: 10)"}
        },
        required: ["node_type", "node_id"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params) do
      node_type = to_string(params[:node_type] || params["node_type"])
      node_id = params[:node_id] || params["node_id"]
      max_depth = params[:max_depth] || params["max_depth"] || 10

      upstream = Graph.trace_upstream(project_id, node_type, node_id, max_depth: max_depth)
      downstream = Graph.trace_downstream(project_id, node_type, node_id, max_depth: max_depth)

      # Resolve center node
      center =
        case Graph.resolve_node(node_type, node_id) do
          {:ok, record} when not is_nil(record) ->
            %{node_type: node_type, node_id: node_id, title: Map.get(record, :title, ""), status: Map.get(record, :status, "")}
          _ ->
            %{node_type: node_type, node_id: node_id, title: "unknown", status: "unknown"}
        end

      # Resolve upstream/downstream titles
      upstream_resolved = resolve_chain(upstream)
      downstream_resolved = resolve_chain(downstream)

      {:ok,
       %{
         trail: %{
           center: center,
           upstream: upstream_resolved,
           downstream: downstream_resolved,
           upstream_count: length(upstream_resolved),
           downstream_count: length(downstream_resolved)
         }
       }}
    end
  end

  @impl true
  def result_summary(%{trail: t}),
    do: "#{t.upstream_count} upstream, #{t.downstream_count} downstream for #{t.center.node_type}##{t.center.node_id}"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp resolve_chain(nodes) do
    refs = Enum.map(nodes, fn n -> {n.node_type, n.node_id} end)
    resolved = Graph.resolve_nodes(refs) |> Map.new(fn {type, id, record} -> {{type, id}, record} end)

    Enum.map(nodes, fn n ->
      record = Map.get(resolved, {n.node_type, n.node_id})

      %{
        node_type: n.node_type,
        node_id: n.node_id,
        edge_kind: n.edge_kind,
        title: if(record, do: Map.get(record, :title, ""), else: ""),
        status: if(record, do: Map.get(record, :status, ""), else: "")
      }
    end)
  end

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
