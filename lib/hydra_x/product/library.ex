defmodule HydraX.Product.Library do
  @moduledoc """
  Source-as-Data: Library is the queryable corpus (spec §4).

  This module is the canonical surface for agents to retrieve source content
  during reasoning and for the web layer to drive the Library UI. It also
  owns source promotion/demotion and source-reference CRUD.

  Conceptual capabilities (spec §4):

    * `search/3`          → semantic + lexical source search
    * `get/2`             → fetch a single source by id
    * `get_content/2`     → fetch source body (or chunked content)
    * `get_for_node/3`    → sources referenced by a given graph node
    * `unprocessed/1`     → sources not yet processed by Researcher
    * `list_recent/2`     → most recently-added sources
    * `promote/1`         → make a source visible in the graph
    * `demote/1`          → hide a source from the graph, keep in Library
    * `archive/1`         → de-emphasise (stays queryable)
    * `reference!/5`      → attach a node → source reference
    * `referenced_by/2`   → list graph nodes that reference a source
  """

  import Ecto.Query

  alias HydraX.Product
  alias HydraX.Product.GraphEdge
  alias HydraX.Product.Source
  alias HydraX.Product.SourceReference
  alias HydraX.Repo

  @default_search_limit 10
  @default_recent_limit 25

  # -------------------------------------------------------------------
  # Read surface
  # -------------------------------------------------------------------

  @doc """
  Semantic + lexical source search, scoped to a project.

  Opts:

    * `:limit` (integer, default 10)
    * `:include_archived` (boolean, default false)
    * `:source_types` (list of strings) — restrict to types
  """
  def search(project_id, query, opts \\ []) do
    project_id = to_int(project_id)
    limit = Keyword.get(opts, :limit, @default_search_limit)

    chunks = Product.search_source_chunks(project_id, query, limit: max(limit * 3, 20))
    include_archived = Keyword.get(opts, :include_archived, false)
    types = Keyword.get(opts, :source_types)

    # Group chunks by source; top score wins per source.
    source_scores =
      Enum.reduce(chunks, %{}, fn ranked, acc ->
        sid = ranked.chunk.source_id

        Map.update(acc, sid, ranked, fn prev ->
          if ranked.score > prev.score, do: ranked, else: prev
        end)
      end)

    # Load the sources that actually matched, ordered by score desc.
    source_ids = Map.keys(source_scores)

    base =
      Source
      |> where([s], s.project_id == ^project_id and s.id in ^source_ids)

    base = if include_archived, do: base, else: where(base, [s], is_nil(s.archived_at))

    base =
      case types do
        nil -> base
        [] -> base
        list -> where(base, [s], s.source_type in ^list)
      end

    sources = Repo.all(base)

    sources
    |> Enum.map(fn s ->
      ranked = Map.fetch!(source_scores, s.id)

      %{
        source: s,
        score: ranked.score,
        top_chunk: %{
          id: ranked.chunk.id,
          ordinal: ranked.chunk.ordinal,
          excerpt: excerpt(ranked.chunk.content)
        }
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Fetch a single source by id, scoped to project.
  Returns `{:ok, source}` or `{:error, :not_found}`.
  """
  def get(project_id, source_id) do
    project_id = to_int(project_id)
    source_id = to_int(source_id)

    case Source
         |> where([s], s.project_id == ^project_id and s.id == ^source_id)
         |> Repo.one() do
      nil -> {:error, :not_found}
      source -> {:ok, source}
    end
  end

  @doc """
  Return the source's full content (or an excerpt if `:max_chars` supplied).
  """
  def get_content(project_id, source_id, opts \\ []) do
    with {:ok, source} <- get(project_id, source_id) do
      max = Keyword.get(opts, :max_chars)
      content = source.content || ""

      content =
        if is_integer(max) and byte_size(content) > max do
          String.slice(content, 0, max)
        else
          content
        end

      {:ok, content}
    end
  end

  @doc """
  Sources referenced by a specific graph node. Spec §4: `library.get_for_node`.
  """
  def get_for_node(project_id, node_type, node_id) do
    project_id = to_int(project_id)
    node_id = to_int(node_id)
    node_type = to_string(node_type)

    SourceReference
    |> where(
      [r],
      r.project_id == ^project_id and
        r.node_type == ^node_type and
        r.node_id == ^node_id
    )
    |> join(:inner, [r], s in assoc(r, :source))
    |> preload([r, s], source: s)
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Sources not yet processed (spec §4).
  """
  def unprocessed(project_id) do
    project_id = to_int(project_id)

    Source
    |> where([s], s.project_id == ^project_id and s.processing_status != "completed")
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Most recent sources in a project.
  """
  def list_recent(project_id, opts \\ []) do
    project_id = to_int(project_id)
    limit = Keyword.get(opts, :limit, @default_recent_limit)

    Source
    |> where([s], s.project_id == ^project_id)
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  List sources by status bucket (spec §6 Library filter chips).
  `bucket` ∈ #{inspect(~w(all unreferenced referenced promoted unprocessed archived))}
  """
  def list_by_bucket(project_id, bucket, opts \\ [])

  def list_by_bucket(project_id, "all", _opts) do
    project_id = to_int(project_id)

    Source
    |> where([s], s.project_id == ^project_id)
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def list_by_bucket(project_id, "archived", _opts) do
    project_id = to_int(project_id)

    Source
    |> where([s], s.project_id == ^project_id and not is_nil(s.archived_at))
    |> order_by([s], desc: s.archived_at)
    |> Repo.all()
  end

  def list_by_bucket(project_id, "promoted", _opts) do
    project_id = to_int(project_id)

    Source
    |> where([s], s.project_id == ^project_id and s.promoted_to_graph == true)
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], desc: s.promoted_at)
    |> Repo.all()
  end

  def list_by_bucket(project_id, "unprocessed", _opts) do
    project_id = to_int(project_id)

    Source
    |> where([s], s.project_id == ^project_id and s.processing_status != "completed")
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def list_by_bucket(project_id, "referenced", _opts) do
    project_id = to_int(project_id)

    referenced_ids =
      SourceReference
      |> where([r], r.project_id == ^project_id)
      |> select([r], r.source_id)
      |> distinct(true)
      |> Repo.all()

    Source
    |> where([s], s.project_id == ^project_id and s.id in ^referenced_ids)
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def list_by_bucket(project_id, "unreferenced", _opts) do
    project_id = to_int(project_id)

    referenced_ids =
      SourceReference
      |> where([r], r.project_id == ^project_id)
      |> select([r], r.source_id)
      |> distinct(true)
      |> Repo.all()

    Source
    |> where([s], s.project_id == ^project_id)
    |> where([s], s.id not in ^referenced_ids)
    |> where([s], is_nil(s.archived_at))
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Promotion / demotion (spec §8)
  # -------------------------------------------------------------------

  @doc """
  Promote a source to a Source graph node. Marks the flag; the graph data
  builder uses it to decide visibility.
  """
  def promote(%Source{} = source) do
    source
    |> Ecto.Changeset.change(%{
      promoted_to_graph: true,
      promoted_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> broadcast("source.promoted")
  end

  def promote(source_id) do
    case Repo.get(Source, to_int(source_id)) do
      nil -> {:error, :not_found}
      s -> promote(s)
    end
  end

  @doc """
  Demote a source back to Library-only. Spec §8: existing graph edges to
  this source are converted to source_references on the opposite node.
  """
  def demote(%Source{} = source) do
    Repo.transaction(fn ->
      convert_graph_edges_to_references(source)

      case source
           |> Ecto.Changeset.change(%{promoted_to_graph: false, promoted_at: nil})
           |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, s} ->
        broadcast({:ok, s}, "source.demoted")
        {:ok, s}

      {:error, _} = err ->
        err
    end
  end

  def demote(source_id) do
    case Repo.get(Source, to_int(source_id)) do
      nil -> {:error, :not_found}
      s -> demote(s)
    end
  end

  @doc """
  Archive (de-emphasise) a source. Remains queryable. References preserved.
  """
  def archive(%Source{} = source) do
    source
    |> Ecto.Changeset.change(%{archived_at: DateTime.utc_now()})
    |> Repo.update()
    |> broadcast("source.archived")
  end

  def unarchive(%Source{} = source) do
    source
    |> Ecto.Changeset.change(%{archived_at: nil})
    |> Repo.update()
    |> broadcast("source.unarchived")
  end

  # -------------------------------------------------------------------
  # References (spec §5)
  # -------------------------------------------------------------------

  @doc """
  Attach a source reference to a graph node.

    * `relationship` ∈ extracted_from / supports / cites / contradicts
    * idempotent on (source_id, node_type, node_id, relationship)
  """
  def reference(project_id, source_id, node_type, node_id, attrs \\ %{}) do
    project_id = to_int(project_id)
    source_id = to_int(source_id)
    node_id = to_int(node_id)
    node_type = to_string(node_type)

    base = %{
      "project_id" => project_id,
      "source_id" => source_id,
      "node_type" => node_type,
      "node_id" => node_id,
      "relationship" => Map.get(attrs, "relationship", Map.get(attrs, :relationship, "cites"))
    }

    extras =
      attrs
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
      |> Map.take(["excerpt", "confidence", "page_or_position", "created_by", "metadata"])

    changeset = SourceReference.changeset(%SourceReference{}, Map.merge(base, extras))

    case Repo.insert(changeset,
           on_conflict: {:replace, [:excerpt, :confidence, :page_or_position, :metadata]},
           conflict_target: [:source_id, :node_type, :node_id, :relationship],
           returning: true
         ) do
      {:ok, ref} ->
        HydraX.Product.PubSub.broadcast_project_event(
          project_id,
          "source_reference.created",
          %{
            reference_id: ref.id,
            source_id: ref.source_id,
            node_type: ref.node_type,
            node_id: ref.node_id,
            relationship: ref.relationship
          }
        )

        {:ok, ref}

      other ->
        other
    end
  end

  @doc """
  Remove a reference row by id.
  """
  def unreference(ref_id) do
    ref_id = to_int(ref_id)

    case Repo.get(SourceReference, ref_id) do
      nil ->
        {:error, :not_found}

      ref ->
        case Repo.delete(ref) do
          {:ok, deleted} ->
            HydraX.Product.PubSub.broadcast_project_event(
              deleted.project_id,
              "source_reference.deleted",
              %{
                reference_id: deleted.id,
                source_id: deleted.source_id,
                node_type: deleted.node_type,
                node_id: deleted.node_id
              }
            )

            {:ok, deleted}

          err ->
            err
        end
    end
  end

  @doc """
  Inverse of `get_for_node/3`: nodes that reference this source.
  Returns raw reference rows with loaded source for UI convenience.
  """
  def referenced_by(project_id, source_id) do
    project_id = to_int(project_id)
    source_id = to_int(source_id)

    SourceReference
    |> where([r], r.project_id == ^project_id and r.source_id == ^source_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Count of sources referenced by a given node (for the node-card badge).
  """
  def reference_count_for_node(project_id, node_type, node_id) do
    project_id = to_int(project_id)
    node_id = to_int(node_id)
    node_type = to_string(node_type)

    SourceReference
    |> where(
      [r],
      r.project_id == ^project_id and
        r.node_type == ^node_type and
        r.node_id == ^node_id
    )
    |> distinct(true)
    |> select([r], r.source_id)
    |> Repo.all()
    |> length()
  end

  @doc """
  Bulk reference counts for every node in a project, keyed by
  `{node_type, node_id}`. Used by the graph data builder.
  """
  def reference_counts_for_project(project_id) do
    project_id = to_int(project_id)

    SourceReference
    |> where([r], r.project_id == ^project_id)
    |> group_by([r], [r.node_type, r.node_id])
    |> select([r], {r.node_type, r.node_id, count(fragment("DISTINCT ?", r.source_id))})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {type, id, count}, acc ->
      Map.put(acc, {type, id}, count)
    end)
  end

  @doc """
  Nodes + counts of who references a given source. Used by Library
  "Referenced by" section.
  """
  def reference_summary(project_id, source_id) do
    refs = referenced_by(project_id, source_id)

    refs
    |> Enum.group_by(& &1.node_type)
    |> Enum.map(fn {type, rows} ->
      %{
        node_type: type,
        count: length(rows),
        nodes:
          Enum.map(rows, fn r ->
            %{
              node_id: r.node_id,
              relationship: r.relationship,
              excerpt: r.excerpt,
              confidence: r.confidence,
              created_at: r.inserted_at
            }
          end)
      }
    end)
  end

  # -------------------------------------------------------------------
  # Promotion proposals (spec §8 agent-proposed)
  # -------------------------------------------------------------------

  @doc """
  Sources that cross the reference-density threshold and are promotion
  candidates. Threshold is tunable; default from spec §8 is 5+ references.
  """
  def promotion_candidates(project_id, opts \\ []) do
    project_id = to_int(project_id)
    threshold = Keyword.get(opts, :threshold, 5)

    counts =
      SourceReference
      |> where([r], r.project_id == ^project_id)
      |> group_by([r], r.source_id)
      |> select([r], {r.source_id, count(r.id)})
      |> Repo.all()

    candidate_ids =
      counts
      |> Enum.filter(fn {_sid, c} -> c >= threshold end)
      |> Enum.map(fn {sid, _} -> sid end)

    if candidate_ids == [] do
      []
    else
      Source
      |> where([s], s.project_id == ^project_id and s.id in ^candidate_ids)
      |> where([s], s.promoted_to_graph == false)
      |> where([s], is_nil(s.archived_at))
      |> Repo.all()
      |> Enum.map(fn s ->
        {_, c} = Enum.find(counts, fn {sid, _} -> sid == s.id end) || {s.id, 0}
        %{source: s, reference_count: c}
      end)
      |> Enum.sort_by(& &1.reference_count, :desc)
    end
  end

  # -------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------

  defp convert_graph_edges_to_references(%Source{} = source) do
    edges =
      GraphEdge
      |> where(
        [e],
        e.project_id == ^source.project_id and
          ((e.from_node_type in ["source", "signal"] and e.from_node_id == ^source.id) or
             (e.to_node_type in ["source", "signal"] and e.to_node_id == ^source.id))
      )
      |> Repo.all()

    Enum.each(edges, fn edge ->
      {node_type, node_id, relationship} =
        cond do
          edge.from_node_type in ["source", "signal"] ->
            {edge.to_node_type, edge.to_node_id, edge_kind_to_relationship(edge.kind, :outgoing)}

          edge.to_node_type in ["source", "signal"] ->
            {edge.from_node_type, edge.from_node_id,
             edge_kind_to_relationship(edge.kind, :incoming)}
        end

      reference(source.project_id, source.id, node_type, node_id, %{
        "relationship" => relationship,
        "created_by" => "system",
        "metadata" => %{"converted_from_edge" => edge.id}
      })

      Repo.delete(edge)
    end)
  end

  defp edge_kind_to_relationship("contradicts", _), do: "contradicts"
  defp edge_kind_to_relationship("extracted_from", _), do: "extracted_from"
  defp edge_kind_to_relationship("derived_from", _), do: "extracted_from"
  defp edge_kind_to_relationship("supports", _), do: "supports"
  defp edge_kind_to_relationship(_, _), do: "cites"

  defp excerpt(nil), do: ""

  defp excerpt(content) do
    content
    |> String.slice(0, 280)
    |> String.trim()
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> raise ArgumentError, "not an integer: #{inspect(v)}"
    end
  end

  defp to_int(v), do: raise(ArgumentError, "cannot coerce #{inspect(v)} to integer")

  defp broadcast({:ok, %Source{} = s} = result, event) do
    HydraX.Product.PubSub.broadcast_project_event(s.project_id, event, %{
      source_id: s.id,
      promoted_to_graph: s.promoted_to_graph,
      archived_at: s.archived_at
    })

    result
  end

  defp broadcast(other, _event), do: other
end
