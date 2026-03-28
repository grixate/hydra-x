defmodule HydraX.Product.Tools.GraphQuery do
  @behaviour HydraX.Tool

  import Ecto.Query

  alias HydraX.Product.ArchitectureNode
  alias HydraX.Product.Decision
  alias HydraX.Product.DesignNode
  alias HydraX.Product.Insight
  alias HydraX.Product.Learning
  alias HydraX.Product.Requirement
  alias HydraX.Product.Strategy
  alias HydraX.Product.Task, as: ProductTask
  alias HydraX.Repo

  @searchable_types %{
    "insight" => Insight,
    "decision" => Decision,
    "strategy" => Strategy,
    "requirement" => Requirement,
    "design_node" => DesignNode,
    "architecture_node" => ArchitectureNode,
    "task" => ProductTask,
    "learning" => Learning
  }

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
        "Semantic search across all product node types (decisions, strategies, insights, requirements, architecture, design, tasks, learnings). Returns the most relevant nodes matching the query.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query text"},
          node_types: %{
            type: "array",
            items: %{type: "string"},
            description: "Filter to specific node types (optional)"
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
      type_filter = params[:node_types] || params["node_types"]

      types =
        if type_filter && type_filter != [],
          do: Map.take(@searchable_types, Enum.map(type_filter, &to_string/1)),
          else: @searchable_types

      results =
        types
        |> Enum.flat_map(fn {type_name, schema} ->
          search_type(schema, project_id, query_text, type_name)
        end)
        |> Enum.sort_by(fn r -> r.rank end, :desc)
        |> Enum.take(limit)

      {:ok, %{results: results, count: length(results)}}
    end
  end

  @impl true
  def result_summary(%{results: results}), do: "found #{length(results)} matching nodes"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp search_type(schema, project_id, query_text, type_name) do
    try do
      schema
      |> where([r], r.project_id == ^project_id)
      |> where(
        [r],
        fragment(
          "search_vector @@ websearch_to_tsquery('english', ?)",
          ^query_text
        )
      )
      |> select([r], {r, fragment("ts_rank(search_vector, websearch_to_tsquery('english', ?))", ^query_text)})
      |> order_by([r], desc: fragment("ts_rank(search_vector, websearch_to_tsquery('english', ?))", ^query_text))
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn {record, rank} ->
        %{
          node_type: type_name,
          node_id: record.id,
          title: record.title,
          body_preview: String.slice(record.body || "", 0, 200),
          status: record.status,
          rank: rank,
          updated_at: record.updated_at
        }
      end)
    rescue
      _ ->
        # Fallback to ILIKE search if tsvector fails
        term = "%#{String.trim(query_text)}%"

        schema
        |> where([r], r.project_id == ^project_id)
        |> where([r], ilike(r.title, ^term) or ilike(r.body, ^term))
        |> order_by([r], desc: r.updated_at)
        |> limit(5)
        |> Repo.all()
        |> Enum.map(fn record ->
          %{
            node_type: type_name,
            node_id: record.id,
            title: record.title,
            body_preview: String.slice(record.body || "", 0, 200),
            status: record.status,
            rank: 0.1,
            updated_at: record.updated_at
          }
        end)
    end
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
