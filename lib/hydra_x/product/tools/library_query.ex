defmodule HydraX.Product.Tools.LibraryQuery do
  @moduledoc """
  Source-as-Data agent tool (spec §4). Exposes the Library API for agent
  reasoning. Agents use this tool — not graph traversal — to retrieve source
  material referenced by nodes, or to search the corpus semantically.
  """

  @behaviour HydraX.Tool

  alias HydraX.Product.Library

  @impl true
  def name, do: "library_query"

  @impl true
  def description,
    do:
      "Query the project Library (sources) by content, by metadata, or by node reference. Sources live in the Library by default; use this to pull relevant source material into your reasoning."

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "library_query",
      description:
        "Retrieve source material from the project Library. Supported operations: search (semantic/lexical), get (single source), content (full body), for_node (sources referenced by a graph node), recent, unprocessed.",
      input_schema: %{
        type: "object",
        properties: %{
          operation: %{
            type: "string",
            enum: ["search", "get", "content", "for_node", "recent", "unprocessed"],
            description: "Which Library operation to perform"
          },
          query: %{type: "string", description: "Search query (operation=search)"},
          source_id: %{
            type: "integer",
            description: "Target source id (operation=get|content)"
          },
          node_type: %{
            type: "string",
            description: "Graph node type for for_node (e.g. insight, decision, requirement)"
          },
          node_id: %{type: "integer", description: "Graph node id for for_node"},
          limit: %{type: "integer", description: "Result limit (default 10)"},
          max_chars: %{
            type: "integer",
            description: "Truncate content to at most this many characters"
          }
        },
        required: ["operation"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    project_id = int(params[:project_id] || params["project_id"])
    operation = params[:operation] || params["operation"]

    with true <- is_integer(project_id) || {:error, :product_project_context_required},
         op when is_binary(op) <- operation do
      run(op, project_id, params)
    else
      _ -> {:error, :product_project_context_required}
    end
  end

  defp run("search", project_id, params) do
    query = to_string(params[:query] || params["query"] || "")
    limit = int(params[:limit] || params["limit"]) || 10

    results = Library.search(project_id, query, limit: limit)

    {:ok,
     %{
       operation: "search",
       results:
         Enum.map(results, fn %{source: s, score: score, top_chunk: chunk} ->
           %{
             source_id: s.id,
             title: s.title,
             source_type: s.source_type,
             score: score,
             excerpt: chunk.excerpt,
             promoted_to_graph: s.promoted_to_graph
           }
         end)
     }}
  end

  defp run("get", project_id, params) do
    id = int(params[:source_id] || params["source_id"])

    with true <- is_integer(id) || {:error, :source_id_required},
         {:ok, s} <- Library.get(project_id, id) do
      {:ok,
       %{
         operation: "get",
         source: %{
           id: s.id,
           title: s.title,
           source_type: s.source_type,
           processing_status: s.processing_status,
           promoted_to_graph: s.promoted_to_graph,
           archived_at: s.archived_at,
           metadata: s.metadata
         }
       }}
    else
      {:error, :not_found} -> {:error, :source_not_found}
      other -> other
    end
  end

  defp run("content", project_id, params) do
    id = int(params[:source_id] || params["source_id"])
    max = int(params[:max_chars] || params["max_chars"])

    with true <- is_integer(id) || {:error, :source_id_required},
         {:ok, content} <- Library.get_content(project_id, id, max_chars: max) do
      {:ok, %{operation: "content", source_id: id, content: content}}
    else
      {:error, :not_found} -> {:error, :source_not_found}
      other -> other
    end
  end

  defp run("for_node", project_id, params) do
    node_type = to_string(params[:node_type] || params["node_type"] || "")
    node_id = int(params[:node_id] || params["node_id"])

    cond do
      node_type == "" ->
        {:error, :node_type_required}

      !is_integer(node_id) ->
        {:error, :node_id_required}

      true ->
        refs = Library.get_for_node(project_id, node_type, node_id)

        {:ok,
         %{
           operation: "for_node",
           node_type: node_type,
           node_id: node_id,
           references:
             Enum.map(refs, fn ref ->
               source = ref.source

               %{
                 reference_id: ref.id,
                 source_id: ref.source_id,
                 relationship: ref.relationship,
                 excerpt: ref.excerpt,
                 confidence: ref.confidence,
                 title: source && source.title,
                 source_type: source && source.source_type
               }
             end)
         }}
    end
  end

  defp run("recent", project_id, params) do
    limit = int(params[:limit] || params["limit"]) || 25

    sources = Library.list_recent(project_id, limit: limit)

    {:ok,
     %{
       operation: "recent",
       sources: Enum.map(sources, &short_source/1)
     }}
  end

  defp run("unprocessed", project_id, _params) do
    sources = Library.unprocessed(project_id)

    {:ok,
     %{
       operation: "unprocessed",
       sources: Enum.map(sources, &short_source/1)
     }}
  end

  defp run(op, _project_id, _params), do: {:error, {:unknown_operation, op}}

  @impl true
  def result_summary(%{operation: op, results: r}) when is_list(r),
    do: "#{op}: #{length(r)} results"

  def result_summary(%{operation: "content", content: c}) when is_binary(c),
    do: "content: #{String.length(c)} chars"

  def result_summary(%{operation: op, references: r}) when is_list(r),
    do: "#{op}: #{length(r)} references"

  def result_summary(%{operation: op, sources: s}) when is_list(s),
    do: "#{op}: #{length(s)} sources"

  def result_summary(%{error: err}), do: to_string(err)
  def result_summary(other), do: inspect(other, limit: 8, printable_limit: 120)

  defp short_source(s) do
    %{
      id: s.id,
      title: s.title,
      source_type: s.source_type,
      processing_status: s.processing_status,
      promoted_to_graph: s.promoted_to_graph
    }
  end

  defp int(v) when is_integer(v), do: v

  defp int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp int(_), do: nil
end
