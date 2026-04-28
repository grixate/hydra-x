defmodule HydraX.Product.Tools.LibraryGaps do
  @moduledoc """
  Library spec §8 — gap detection as a Researcher tool. Lets the agent
  answer "what am I missing about X" and "where are my biggest gaps" by
  pulling structured gap data from `HydraX.Product.LibraryGaps`.
  """

  @behaviour HydraX.Tool

  alias HydraX.Product.LibraryGaps

  @impl true
  def name, do: "library_gaps"

  @impl true
  def description,
    do:
      "Detect blind spots in the project Library: sparse topics, recency gaps, author monocultures, and citation gaps. Use when answering 'what am I missing' or surfacing where the corpus is thin."

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "library_gaps",
      description:
        "Return Library blind spots. Operations: sparse_topics, recency_gaps, author_monocultures, citation_gaps, summary (all four).",
      input_schema: %{
        type: "object",
        properties: %{
          operation: %{
            type: "string",
            enum: [
              "sparse_topics",
              "recency_gaps",
              "author_monocultures",
              "citation_gaps",
              "summary"
            ],
            description: "Which gap query to run"
          },
          threshold: %{
            type: "integer",
            description: "Sparse-topic threshold (default 2)"
          },
          years_threshold: %{
            type: "integer",
            description: "Recency-gap threshold in years (default 3)"
          },
          ratio: %{
            type: "number",
            description: "Author-monoculture ratio threshold 0-1 (default 0.7)"
          }
        },
        required: ["operation"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    project_id = int(params[:project_id] || params["project_id"])
    op = params[:operation] || params["operation"]

    cond do
      !is_integer(project_id) ->
        {:error, :product_project_context_required}

      !is_binary(op) ->
        {:error, :operation_required}

      true ->
        run(op, project_id, params)
    end
  end

  defp run("sparse_topics", project_id, params) do
    threshold = int(params[:threshold] || params["threshold"]) || 2
    rows = LibraryGaps.sparse_topics(project_id, threshold: threshold)
    {:ok, %{operation: "sparse_topics", topics: Enum.map(rows, &topic_row/1)}}
  end

  defp run("recency_gaps", project_id, params) do
    years = int(params[:years_threshold] || params["years_threshold"]) || 3
    rows = LibraryGaps.recency_gaps(project_id, years_threshold: years)

    {:ok,
     %{
       operation: "recency_gaps",
       topics:
         Enum.map(rows, fn r ->
           Map.merge(topic_row(r), %{
             newest_at: r.newest_at && DateTime.to_iso8601(r.newest_at)
           })
         end)
     }}
  end

  defp run("author_monocultures", project_id, params) do
    ratio = num(params[:ratio] || params["ratio"]) || 0.7
    rows = LibraryGaps.author_monocultures(project_id, ratio: ratio)

    {:ok,
     %{
       operation: "author_monocultures",
       topics:
         Enum.map(rows, fn r ->
           %{
             topic_id: r.topic.id,
             topic_title: r.topic.title,
             dominant_author_id: r.dominant_author && r.dominant_author.id,
             dominant_author_name: r.dominant_author && r.dominant_author.title,
             share: r.share,
             source_count: r.source_count
           }
         end)
     }}
  end

  defp run("citation_gaps", project_id, _params) do
    rows = LibraryGaps.citation_gaps(project_id)

    {:ok,
     %{
       operation: "citation_gaps",
       sources:
         Enum.map(rows, fn r ->
           %{
             source_id: r.source.id,
             source_title: r.source.title,
             cited_works_count: r.cited_works_count,
             cites_in_library: r.cites_in_library,
             gap: r.gap
           }
         end)
     }}
  end

  defp run("summary", project_id, _params) do
    bundle = LibraryGaps.summarise(project_id)

    {:ok,
     %{
       operation: "summary",
       sparse_topic_count: length(bundle.sparse_topics),
       recency_gap_count: length(bundle.recency_gaps),
       monoculture_count: length(bundle.author_monocultures),
       citation_gap_count: length(bundle.citation_gaps),
       sparse_topics: Enum.take(Enum.map(bundle.sparse_topics, &topic_row/1), 10),
       top_recency_gaps:
         Enum.take(
           Enum.map(bundle.recency_gaps, fn r ->
             Map.merge(topic_row(r), %{
               newest_at: r.newest_at && DateTime.to_iso8601(r.newest_at)
             })
           end),
           10
         )
     }}
  end

  defp run(op, _project_id, _params), do: {:error, {:unknown_operation, op}}

  @impl true
  def result_summary(%{operation: "summary"} = result) do
    "Library gaps — sparse: #{result.sparse_topic_count}, " <>
      "recency: #{result.recency_gap_count}, " <>
      "monoculture: #{result.monoculture_count}, " <>
      "citation: #{result.citation_gap_count}"
  end

  def result_summary(%{operation: op, topics: t}) when is_list(t),
    do: "#{op}: #{length(t)} topics"

  def result_summary(%{operation: op, sources: s}) when is_list(s),
    do: "#{op}: #{length(s)} sources"

  def result_summary(other), do: inspect(other, limit: 8, printable_limit: 120)

  defp topic_row(%{topic: t, source_count: c}) do
    %{topic_id: t.id, topic_title: t.title, source_count: c}
  end

  defp int(v) when is_integer(v), do: v

  defp int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp int(_), do: nil

  defp num(v) when is_number(v), do: v

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp num(_), do: nil
end
