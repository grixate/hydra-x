defmodule HydraX.Product.Tools.SourceSearch do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "source_search"

  @impl true
  def description, do: "Search product research sources and return grounded citation chunks"

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "source_search",
      description:
        "Search project sources for grounded evidence. Use this before making factual claims about the product, users, requirements, or research findings.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query to match against indexed sources"},
          limit: %{
            type: "integer",
            description: "Maximum number of source chunks to return (default: 5)"
          }
        },
        required: ["query"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    project_id =
      case params[:project_id] || params["project_id"] do
        value when is_integer(value) ->
          value

        value when is_binary(value) ->
          case Integer.parse(value) do
            {integer, ""} -> integer
            _ -> nil
          end

        _ ->
          nil
      end

    query = params[:query] || params["query"] || ""
    limit = params[:limit] || params["limit"] || 5

    if is_integer(project_id) and String.trim(to_string(query)) != "" do
      results =
        Product.search_source_chunks(project_id, query, limit: limit)
        |> Enum.map(fn ranked ->
          chunk = ranked.chunk

          %{
            chunk_id: chunk.id,
            source_id: chunk.source_id,
            source_title: chunk.source.title,
            source_type: chunk.source.source_type,
            content: chunk.content,
            section: get_in(chunk.metadata || %{}, ["section"]),
            score: ranked.score,
            lexical_score: ranked.lexical_score,
            vector_score: ranked.vector_score,
            reasons: ranked.reasons
          }
        end)

      {:ok, %{results: results}}
    else
      {:error, :product_project_context_required}
    end
  end

  @impl true
  def result_summary(%{results: results}), do: "retrieved #{length(results)} source chunks"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
