defmodule HydraX.Product.LibraryGaps do
  @moduledoc """
  Library spec §8 — reactive gap detection. V1 surfaces four gap types on
  demand (the Researcher tool exposes these to chat answers; the Topic
  browser uses sparse-topic data directly). Proactive Stream reports are
  V1.1.

  Gap types:

    * `sparse_topics/2`     — topics with `< N` sources (default N=2)
    * `recency_gaps/2`      — topics whose newest source is older than `N` years
    * `author_monocultures/2` — topics where ≥ `ratio` of sources share an author
    * `citation_gaps/2`     — sources that cite works not in the Library
  """

  import Ecto.Query

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Graph.NodeRelationship
  alias HydraX.Repo

  @default_sparse_threshold 2
  @default_recency_years 3
  @default_monoculture_ratio 0.7

  @doc """
  Topics with fewer than `threshold` (default 2) is_about-from-source edges.
  Returns `[%{topic: %GraphNode{}, source_count: integer}]` sorted ascending
  by count.
  """
  def sparse_topics(project_id, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_sparse_threshold)
    project_id = int(project_id)

    counts = topic_source_counts(project_id)
    topics = list_topics(project_id)

    topics
    |> Enum.map(fn t ->
      %{topic: t, source_count: Map.get(counts, t.id, 0)}
    end)
    |> Enum.filter(&(&1.source_count < threshold))
    |> Enum.sort_by(& &1.source_count, :asc)
  end

  @doc """
  Topics whose newest source's recency (or insertion date) is older than
  `years_threshold`. Returns `[%{topic, newest_recency, source_count}]`.
  """
  def recency_gaps(project_id, opts \\ []) do
    years = Keyword.get(opts, :years_threshold, @default_recency_years)
    project_id = int(project_id)
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -years * 365 * 86_400, :second)

    counts = topic_source_counts(project_id)

    topic_ids =
      list_topics(project_id)
      |> Enum.map(& &1.id)

    newest_per_topic =
      from(r in NodeRelationship,
        where:
          r.project_id == ^project_id and r.type_key == "is_about" and
            r.from_node_type == "source" and r.to_node_id in ^topic_ids,
        join: s in GraphNode,
        on: s.id == r.from_node_id,
        group_by: r.to_node_id,
        select: {
          r.to_node_id,
          max(s.inserted_at)
        }
      )
      |> Repo.all()
      |> Map.new()

    list_topics(project_id)
    |> Enum.flat_map(fn topic ->
      case Map.get(newest_per_topic, topic.id) do
        nil ->
          []

        %DateTime{} = newest ->
          if DateTime.compare(newest, cutoff) == :lt do
            [
              %{
                topic: topic,
                newest_at: newest,
                source_count: Map.get(counts, topic.id, 0)
              }
            ]
          else
            []
          end
      end
    end)
    |> Enum.sort_by(& &1.newest_at, {:asc, DateTime})
  end

  @doc """
  Topics where `ratio` (default 0.7) of sources share at least one author.
  Returns `[%{topic, dominant_author, share, source_count}]`.
  """
  def author_monocultures(project_id, opts \\ []) do
    min_ratio = Keyword.get(opts, :ratio, @default_monoculture_ratio)
    project_id = int(project_id)

    topic_to_sources = topic_to_source_ids(project_id)
    source_to_authors = source_to_author_ids(project_id)

    list_topics(project_id)
    |> Enum.flat_map(fn topic ->
      sids = Map.get(topic_to_sources, topic.id, [])

      if length(sids) < 2 do
        []
      else
        author_share =
          sids
          |> Enum.flat_map(fn sid -> Map.get(source_to_authors, sid, []) end)
          |> Enum.frequencies()

        case Enum.max_by(author_share, fn {_, count} -> count end, fn -> nil end) do
          nil ->
            []

          {author_id, count} ->
            share = count / length(sids)

            if share >= min_ratio do
              author = Repo.get(GraphNode, author_id)

              [
                %{
                  topic: topic,
                  dominant_author: author,
                  share: Float.round(share, 2),
                  source_count: length(sids)
                }
              ]
            else
              []
            end
        end
      end
    end)
    |> Enum.sort_by(& &1.share, :desc)
  end

  @doc """
  Sources whose preprocessing recorded a citation count that exceeds the
  number of `cites` edges to other Library sources. Returns
  `[%{source, cited_works_count, cites_in_library, gap}]`.
  """
  def citation_gaps(project_id, opts \\ []) do
    project_id = int(project_id)
    min_gap = Keyword.get(opts, :min_gap, 1)

    sources =
      from(n in GraphNode,
        where: n.project_id == ^project_id and n.type_key == "source" and is_nil(n.archived_at)
      )
      |> Repo.all()

    cites_counts =
      from(r in NodeRelationship,
        where:
          r.project_id == ^project_id and r.type_key == "cites" and
            r.from_node_type == "source",
        group_by: r.from_node_id,
        select: {r.from_node_id, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    sources
    |> Enum.flat_map(fn s ->
      attrs = s.attributes || %{}
      cited = Map.get(attrs, "cited_works_count") || 0
      in_lib = Map.get(cites_counts, s.id, 0)
      gap = cited - in_lib

      if cited > 0 and gap >= min_gap do
        [
          %{
            source: s,
            cited_works_count: cited,
            cites_in_library: in_lib,
            gap: gap
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.gap, :desc)
  end

  @doc """
  Bundle all four gap categories for a single response. Used by the
  Researcher tool when the user asks "what am I missing about X" or
  "where are my biggest gaps."
  """
  def summarise(project_id, opts \\ []) do
    %{
      sparse_topics: sparse_topics(project_id, opts),
      recency_gaps: recency_gaps(project_id, opts),
      author_monocultures: author_monocultures(project_id, opts),
      citation_gaps: citation_gaps(project_id, opts)
    }
  end

  # ---------------------------------------------------------------
  # Internal queries
  # ---------------------------------------------------------------

  defp list_topics(project_id) do
    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "topic" and is_nil(n.archived_at)
    )
    |> Repo.all()
  end

  defp topic_source_counts(project_id) do
    from(r in NodeRelationship,
      where:
        r.project_id == ^project_id and r.type_key == "is_about" and
          r.from_node_type == "source",
      group_by: r.to_node_id,
      select: {r.to_node_id, count(r.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp topic_to_source_ids(project_id) do
    from(r in NodeRelationship,
      where:
        r.project_id == ^project_id and r.type_key == "is_about" and
          r.from_node_type == "source",
      select: {r.to_node_id, r.from_node_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {topic_id, _} -> topic_id end, fn {_, source_id} -> source_id end)
  end

  defp source_to_author_ids(project_id) do
    from(r in NodeRelationship,
      where:
        r.project_id == ^project_id and r.type_key == "authored_by" and
          r.from_node_type == "source",
      select: {r.from_node_id, r.to_node_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {source_id, _} -> source_id end, fn {_, author_id} -> author_id end)
  end

  defp int(v) when is_integer(v), do: v

  defp int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> raise ArgumentError, "not an integer: #{inspect(v)}"
    end
  end
end
