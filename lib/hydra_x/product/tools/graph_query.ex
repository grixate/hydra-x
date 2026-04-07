defmodule HydraX.Product.Tools.GraphQuery do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "graph_query"

  @impl true
  def description, do: "Search across all product graph node types"

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "graph_query",
      description:
        "Semantic search across all product node types (decisions, strategies, insights, requirements, architecture, design, tasks, and learnings). Supports routed product memory search by hall, topic, and time.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query text"},
          node_types: %{
            type: "array",
            items: %{type: "string"},
            description: "Filter to specific node types"
          },
          hall: %{type: "string", description: "Optional hall to prioritize"},
          topic_key: %{type: "string", description: "Optional topic key to prioritize"},
          as_of: %{
            type: "string",
            description: "Optional ISO datetime for temporal truth filtering"
          },
          limit: %{type: "integer", description: "Max results (default: 10)"}
        },
        required: ["query"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params) do
      query_text = params[:query] || params["query"] || ""
      limit = params[:limit] || params["limit"] || 10
      type_filter = params[:node_types] || params["node_types"] || []

      results =
        Product.search_graph_nodes(project_id, query_text,
          node_types: type_filter,
          hall: params[:hall] || params["hall"],
          topic_key: params[:topic_key] || params["topic_key"],
          as_of: params[:as_of] || params["as_of"],
          limit: limit
        )

      {:ok, %{results: results, count: length(results)}}
    end
  end

  @impl true
  def result_summary(%{results: results}), do: "found #{length(results)} matching nodes"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp extract_project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end

      _ ->
        {:error, :product_project_context_required}
    end
  end
end
