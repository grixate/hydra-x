defmodule HydraX.Product.Tools.PatternCheck do
  @behaviour HydraX.Tool

  import Ecto.Query
  alias HydraX.Product.DesignNode
  alias HydraX.Repo

  @impl true
  def name, do: "pattern_check"

  @impl true
  def description, do: "Search for similar design patterns in the project"

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "pattern_check",
      description:
        "Search existing design nodes for similar patterns to check for consistency. Returns design nodes with similar titles or bodies.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query describing the pattern to check"},
          limit: %{type: "integer", description: "Max results (default: 5)"}
        },
        required: ["query"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params) do
      query = params[:query] || params["query"] || ""
      limit = params[:limit] || params["limit"] || 5
      term = "%#{String.trim(query)}%"

      results =
        DesignNode
        |> where([d], d.project_id == ^project_id)
        |> where([d], ilike(d.title, ^term) or ilike(d.body, ^term))
        |> order_by([d], desc: d.updated_at)
        |> limit(^limit)
        |> Repo.all()
        |> Enum.map(fn node ->
          %{
            id: node.id,
            title: node.title,
            node_type: node.node_type,
            status: node.status,
            body_preview: String.slice(node.body || "", 0, 200)
          }
        end)

      {:ok, %{similar_patterns: results, count: length(results)}}
    end
  end

  @impl true
  def result_summary(%{similar_patterns: patterns}), do: "found #{length(patterns)} similar patterns"
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
