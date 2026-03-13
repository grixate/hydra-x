defmodule HydraX.Memory do
  @moduledoc """
  Typed graph memory storage with lexical search and markdown export.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias HydraX.Embeddings
  alias HydraX.Memory.{Edge, Entry, Markdown}
  alias HydraX.Repo

  def get_memory!(id), do: Repo.get!(Entry, id)

  def status_counts(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)

    Entry
    |> maybe_filter_agent(agent_id)
    |> group_by([entry], entry.status)
    |> select([entry], {entry.status, count(entry.id)})
    |> Repo.all()
    |> Enum.into(%{}, fn {status, count} -> {status, count} end)
  end

  def list_memories(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    type = Keyword.get(opts, :type)
    status = Keyword.get(opts, :status)
    min_importance = Keyword.get(opts, :min_importance)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(type)
    |> maybe_filter_status(status)
    |> maybe_filter_min_importance(min_importance)
    |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
    |> preload([:conversation])
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def embedding_status(agent_id \\ nil) do
    embedding_runtime = Embeddings.status()

    entries =
      Entry
      |> maybe_filter_agent(agent_id)
      |> select([entry], %{metadata: entry.metadata, updated_at: entry.updated_at})
      |> Repo.all()

    {embedded_count, unembedded_count, stale_count, fallback_count, backend_counts, model_counts,
     last_generated_at} =
      Enum.reduce(entries, {0, 0, 0, 0, %{}, %{}, nil}, fn entry,
                                                           {embedded, unembedded, stale, fallback,
                                                            backends, models, last_generated} ->
        metadata = entry.metadata || %{}
        embedded? = embedded_memory?(metadata)
        backend = metadata["embedding_backend"]
        model = metadata["embedding_model"]
        fallback_from = metadata["embedding_fallback_from"]
        generated_at = metadata["embedding_generated_at"]

        {
          embedded + if(embedded?, do: 1, else: 0),
          unembedded + if(embedded?, do: 0, else: 1),
          stale + if(stale_embedding?(metadata, embedding_runtime), do: 1, else: 0),
          fallback + if(is_binary(fallback_from) and fallback_from != "", do: 1, else: 0),
          increment_count(backends, backend),
          increment_count(models, model),
          max_timestamp(last_generated, normalize_datetime(generated_at) || entry.updated_at)
        }
      end)

    %{
      total_count: length(entries),
      embedded_count: embedded_count,
      unembedded_count: unembedded_count,
      stale_count: stale_count,
      fallback_count: fallback_count,
      backend_counts: backend_counts,
      model_counts: model_counts,
      last_generated_at: last_generated_at,
      configured_backend: embedding_runtime.configured_backend,
      active_backend: embedding_runtime.active_backend,
      configured_model: embedding_runtime.configured_model,
      active_model: embedding_runtime.active_model,
      fallback_enabled?: embedding_runtime.fallback_enabled?,
      degraded?: embedding_runtime.degraded?,
      url_configured?: embedding_runtime.url_configured?,
      api_key_configured?: embedding_runtime.api_key_configured?
    }
  end

  def search(agent_id, query, limit \\ 8, opts \\ [])

  def search(agent_id, "", limit, opts),
    do: list_memories(Keyword.merge(opts, agent_id: agent_id, limit: limit))

  def search(agent_id, nil, limit, opts),
    do: list_memories(Keyword.merge(opts, agent_id: agent_id, limit: limit))

  def search(agent_id, query, limit, opts) do
    search_ranked(agent_id, query, limit, opts)
    |> Enum.map(& &1.entry)
  end

  def search_ranked(agent_id, "", limit, opts) do
    list_memories(Keyword.merge(opts, agent_id: agent_id, limit: limit))
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      score_breakdown = %{
        "recent_list" => round_score(1.0 - index * 0.01),
        "importance" => round_score(importance_boost(entry))
      }

      %{
        entry: entry,
        score:
          score_breakdown
          |> Map.values()
          |> Enum.sum()
          |> round_score(),
        vector_score: nil,
        lexical_rank: nil,
        semantic_rank: nil,
        score_breakdown: score_breakdown,
        reasons: ["recent memory list", importance_reason(entry)]
      }
    end)
  end

  def search_ranked(agent_id, nil, limit, opts), do: search_ranked(agent_id, "", limit, opts)

  def search_ranked(agent_id, query, limit, opts) do
    search_opts = search_opts(opts)
    query_context = build_query_context(query)
    lexical_results = lexical_search(agent_id, query, max(limit * 3, 12), search_opts)

    semantic_results =
      semantic_search(agent_id, query, max(limit * 4, 20), search_opts, query_context)

    lexical_ranks =
      lexical_results
      |> Enum.with_index(1)
      |> Map.new(fn {entry, rank} -> {entry.id, {entry, rank}} end)

    semantic_ranks =
      semantic_results
      |> Enum.with_index(1)
      |> Map.new(fn {entry, rank} -> {entry.id, {entry, rank}} end)

    lexical_ranks
    |> Map.keys()
    |> Kernel.++(Map.keys(semantic_ranks))
    |> Enum.uniq()
    |> Enum.map(fn id ->
      {entry, lexical_rank} =
        Map.get_lazy(lexical_ranks, id, fn -> Map.fetch!(semantic_ranks, id) end)

      semantic_rank =
        case Map.get(semantic_ranks, id) do
          {_entry, rank} -> rank
          nil -> nil
        end

      vector_score = vector_similarity(entry, query_context)

      score_breakdown =
        search_score_breakdown(entry, lexical_rank, semantic_rank, query_context, query)

      %{
        entry: entry,
        score: score_breakdown |> Map.values() |> Enum.sum() |> round_score(),
        vector_score: round_score(vector_score),
        lexical_rank: lexical_rank,
        semantic_rank: semantic_rank,
        score_breakdown: score_breakdown,
        reasons: hybrid_reasons(entry, lexical_rank, semantic_rank, query_context, query)
      }
    end)
    |> Enum.sort_by(
      &{-&1.score, lexical_rank_order(&1.lexical_rank), lexical_rank_order(&1.semantic_rank),
       -&1.entry.importance}
    )
    |> Enum.take(limit)
  end

  def search_ranked(agent_id, query, limit), do: search_ranked(agent_id, query, limit, [])

  def bulletin_ranked(agent_id, limit \\ 12, opts \\ []) do
    search_opts =
      opts
      |> search_opts()
      |> then(fn search_opts ->
        if is_nil(search_opts.status),
          do: Map.put(search_opts, :status, "active"),
          else: search_opts
      end)

    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(search_opts.type)
    |> maybe_filter_status(search_opts.status)
    |> maybe_filter_min_importance(search_opts.min_importance)
    |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
    |> limit(^max(limit * 4, 48))
    |> Repo.all()
    |> Enum.map(fn entry ->
      %{
        entry: entry,
        score: bulletin_score(entry) |> round_score(),
        reasons: bulletin_reasons(entry)
      }
    end)
    |> Enum.sort_by(&{-&1.score, -&1.entry.importance})
    |> Enum.take(limit)
  end

  def create_memory(attrs) do
    result =
      %Entry{}
      |> Entry.changeset(enrich_memory_attrs(attrs))
      |> Repo.insert()

    with {:ok, entry} <- result do
      maybe_refresh_cortex(entry.agent_id)
      broadcast_memory(entry.agent_id)
      {:ok, entry}
    end
  end

  def change_memory(entry \\ %Entry{}, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end

  def update_memory(%Entry{} = entry, attrs) do
    result =
      entry
      |> Entry.changeset(enrich_memory_attrs(attrs, entry))
      |> Repo.update()

    with {:ok, updated} <- result do
      maybe_refresh_cortex(updated.agent_id)
      broadcast_memory(updated.agent_id)
      {:ok, updated}
    end
  end

  def delete_memory!(id) do
    entry = get_memory!(id)
    Repo.delete!(entry)
    broadcast_memory(entry.agent_id)
    entry
  end

  def reconcile_memory!(source_id, target_id, mode, opts \\ []) do
    source = get_memory!(source_id)
    target = get_memory!(target_id)

    if source.id == target.id do
      raise ArgumentError, "source and target memories must be different"
    end

    if source.agent_id != target.agent_id do
      raise ArgumentError, "memories must belong to the same agent"
    end

    result =
      Repo.transaction(fn ->
        target_metadata = target.metadata || %{}
        source_status = if mode == :merge, do: "merged", else: "superseded"
        target_content = Keyword.get(opts, :content, target.content)

        merged_from_ids =
          target_metadata
          |> Map.get("merged_from_ids", [])
          |> List.wrap()
          |> Kernel.++([source.id])
          |> Enum.uniq()

        {:ok, updated_target} =
          target
          |> Entry.changeset(%{
            content: target_content,
            metadata:
              target_metadata
              |> Map.put("merged_from_ids", merged_from_ids)
              |> Map.put("last_reconciled_at", DateTime.utc_now())
              |> enriched_memory_metadata(%{
                content: target_content,
                type: target.type,
                status: target.status,
                importance: target.importance
              })
          })
          |> Repo.update()

        {:ok, updated_source} =
          source
          |> Entry.changeset(%{
            status: source_status,
            metadata:
              (source.metadata || %{})
              |> Map.put("reconciled_into_id", target.id)
              |> Map.put("reconciliation_mode", Atom.to_string(mode))
              |> Map.put("reconciled_at", DateTime.utc_now())
          })
          |> Repo.update()

        {:ok, edge} =
          link_memories(%{
            from_memory_id: target.id,
            to_memory_id: source.id,
            kind: "supersedes",
            weight: 1.0,
            metadata: %{"mode" => Atom.to_string(mode)}
          })

        %{source: updated_source, target: updated_target, edge: edge}
      end)

    with {:ok, reconciled} <- unwrap_transaction(result) do
      maybe_refresh_cortex(reconciled.target.agent_id)
      broadcast_memory(reconciled.target.agent_id)
      {:ok, reconciled}
    end
  end

  def conflict_memory!(source_id, target_id, opts \\ []) do
    source = get_memory!(source_id)
    target = get_memory!(target_id)
    reason = Keyword.get(opts, :reason)

    if source.id == target.id do
      raise ArgumentError, "source and target memories must be different"
    end

    if source.agent_id != target.agent_id do
      raise ArgumentError, "memories must belong to the same agent"
    end

    result =
      Repo.transaction(fn ->
        conflicted_at = DateTime.utc_now()

        {:ok, updated_source} =
          source
          |> Entry.changeset(%{
            status: "conflicted",
            metadata: conflict_metadata(source.metadata, target.id, reason, conflicted_at)
          })
          |> Repo.update()

        {:ok, updated_target} =
          target
          |> Entry.changeset(%{
            status: "conflicted",
            metadata: conflict_metadata(target.metadata, source.id, reason, conflicted_at)
          })
          |> Repo.update()

        {:ok, edge} =
          link_memories(%{
            from_memory_id: source.id,
            to_memory_id: target.id,
            kind: "contradicts",
            weight: 1.0,
            metadata:
              %{"reason" => reason, "conflicted_at" => conflicted_at}
              |> Enum.reject(fn {_key, value} -> is_nil(value) end)
              |> Map.new()
          })

        %{source: updated_source, target: updated_target, edge: edge}
      end)

    with {:ok, conflicted} <- unwrap_transaction(result) do
      log_conflict_event(conflicted, reason)
      maybe_refresh_cortex(conflicted.target.agent_id)
      broadcast_memory(conflicted.target.agent_id)
      {:ok, conflicted}
    end
  end

  def resolve_conflict!(winner_id, loser_id, opts \\ []) do
    winner = get_memory!(winner_id)
    loser = get_memory!(loser_id)
    note = Keyword.get(opts, :note)
    loser_status = Keyword.get(opts, :loser_status, "superseded")

    if winner.id == loser.id do
      raise ArgumentError, "winner and loser memories must be different"
    end

    if winner.agent_id != loser.agent_id do
      raise ArgumentError, "memories must belong to the same agent"
    end

    result =
      Repo.transaction(fn ->
        resolved_at = DateTime.utc_now()
        winner_content = Keyword.get(opts, :content, winner.content)

        {:ok, updated_winner} =
          winner
          |> Entry.changeset(%{
            status: "active",
            content: winner_content,
            metadata:
              winner.metadata
              |> resolve_conflict_metadata(loser.id, resolved_at, note)
              |> enriched_memory_metadata(%{
                content: winner_content,
                type: winner.type,
                status: "active",
                importance: winner.importance
              })
          })
          |> Repo.update()

        {:ok, updated_loser} =
          loser
          |> Entry.changeset(%{
            status: loser_status,
            metadata:
              loser.metadata
              |> resolve_conflict_metadata(winner.id, resolved_at, note)
              |> Map.put("reconciled_into_id", winner.id)
              |> Map.put("reconciliation_mode", "resolve_conflict")
              |> Map.put("resolved_conflict_at", resolved_at)
          })
          |> Repo.update()

        {:ok, edge} =
          link_memories(%{
            from_memory_id: winner.id,
            to_memory_id: loser.id,
            kind: "supersedes",
            weight: 1.0,
            metadata:
              %{"mode" => "resolve_conflict", "note" => note, "resolved_at" => resolved_at}
              |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
              |> Map.new()
          })

        resolved_events = resolve_conflict_events(updated_winner, updated_loser, note)

        %{
          winner: updated_winner,
          loser: updated_loser,
          edge: edge,
          resolved_events: resolved_events
        }
      end)

    with {:ok, resolved} <- unwrap_transaction(result) do
      maybe_refresh_cortex(resolved.winner.agent_id)
      broadcast_memory(resolved.winner.agent_id)
      {:ok, resolved}
    end
  end

  def link_memories(attrs) do
    %Edge{}
    |> Edge.changeset(attrs)
    |> Repo.insert()
  end

  def delete_edge!(id) do
    edge = Repo.get!(Edge, id)
    Repo.delete!(edge)
  end

  def change_edge(edge \\ %Edge{}, attrs \\ %{}) do
    Edge.changeset(edge, attrs)
  end

  def list_edges_for(memory_id) do
    Edge
    |> where([edge], edge.from_memory_id == ^memory_id or edge.to_memory_id == ^memory_id)
    |> preload([:from_memory, :to_memory])
    |> order_by([edge], desc: edge.inserted_at)
    |> Repo.all()
  end

  def render_markdown(agent_id) do
    list_memories(agent_id: agent_id, limit: 500, status: "active")
    |> Markdown.render()
  end

  def sync_markdown(%HydraX.Runtime.AgentProfile{} = agent) do
    content = render_markdown(agent.id)
    path = Path.join([agent.workspace_root, "memory", "MEMORY.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content <> "\n")
    {:ok, path}
  end

  defp maybe_filter_agent(query, nil), do: query
  defp maybe_filter_agent(query, agent_id), do: where(query, [entry], entry.agent_id == ^agent_id)

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, ""), do: query
  defp maybe_filter_type(query, type), do: where(query, [entry], entry.type == ^type)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, "all"), do: query
  defp maybe_filter_status(query, status), do: where(query, [entry], entry.status == ^status)

  defp maybe_filter_min_importance(query, nil), do: query

  defp maybe_filter_min_importance(query, min_importance),
    do: where(query, [entry], entry.importance >= ^min_importance)

  defp maybe_refresh_cortex(nil), do: :ok

  defp maybe_refresh_cortex(agent_id) do
    if Registry.lookup(HydraX.ProcessRegistry, {:cortex, agent_id}) != [] do
      HydraX.Agent.Cortex.refresh(agent_id)
    end
  end

  defp broadcast_memory(agent_id) do
    Phoenix.PubSub.broadcast(HydraX.PubSub, "memory", {:memory_updated, agent_id})
  end

  defp log_conflict_event(%{source: source, target: target}, reason) do
    HydraX.Safety.log_event(%{
      agent_id: source.agent_id,
      conversation_id: source.conversation_id || target.conversation_id,
      category: "memory",
      level: "warn",
      message: "Memory conflict flagged between #{source.id} and #{target.id}",
      metadata:
        %{
          "source_id" => source.id,
          "target_id" => target.id,
          "reason" => reason
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
        |> Map.new()
    })

    :ok
  end

  defp resolve_conflict_events(winner, loser, note) do
    HydraX.Safety.list_events(agent_id: winner.agent_id, category: "memory", limit: 100)
    |> Enum.filter(&matching_conflict_event?(&1, winner.id, loser.id))
    |> Enum.reject(&(&1.status == "resolved"))
    |> Enum.map(fn event ->
      reason =
        ["Resolved in favor of memory #{winner.id}", note]
        |> Enum.reject(&is_nil_or_empty/1)
        |> Enum.join(": ")

      HydraX.Safety.resolve_event!(event.id, "memory_reconciliation", reason)
    end)
  end

  defp matching_conflict_event?(event, first_id, second_id) do
    source_id = get_in(event.metadata, ["source_id"])
    target_id = get_in(event.metadata, ["target_id"])
    ids = MapSet.new([source_id, target_id])

    ids == MapSet.new([first_id, second_id])
  end

  defp resolve_conflict_metadata(metadata, counterpart_id, resolved_at, note) do
    remaining_conflicts =
      metadata
      |> Kernel.||(%{})
      |> Map.get("conflict_with_ids", [])
      |> List.wrap()
      |> Enum.reject(&(&1 == counterpart_id))

    metadata
    |> Kernel.||(%{})
    |> Map.delete("conflict_with_ids")
    |> Map.delete("conflict_reason")
    |> Map.delete("conflicted_at")
    |> maybe_put("conflict_with_ids", remaining_conflicts)
    |> maybe_put("conflict_resolved_at", resolved_at)
    |> maybe_put("conflict_resolution_note", note)
  end

  defp conflict_metadata(metadata, counterpart_id, reason, conflicted_at) do
    existing_ids =
      metadata
      |> Kernel.||(%{})
      |> Map.get("conflict_with_ids", [])
      |> List.wrap()

    %{
      "conflict_with_ids" => Enum.uniq(existing_ids ++ [counterpart_id]),
      "conflicted_at" => conflicted_at
    }
    |> maybe_put("conflict_reason", reason)
    |> then(&Map.merge(metadata || %{}, &1))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false

  defp fts_query(query) do
    query
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" OR ", &"\"#{&1}\"")
  end

  defp search_opts(opts) do
    %{
      type: Keyword.get(opts, :type),
      status: Keyword.get(opts, :status),
      min_importance: Keyword.get(opts, :min_importance)
    }
  end

  defp lexical_search(agent_id, query, limit, search_opts) do
    try do
      sql = """
      SELECT m.*
      FROM memory_search ms
      JOIN memory_entries m ON m.id = ms.rowid
      WHERE ms.content MATCH ?
        AND (? IS NULL OR m.agent_id = ?)
        AND (? IS NULL OR m.type = ?)
        AND (? IS NULL OR m.status = ?)
        AND (? IS NULL OR m.importance >= ?)
      ORDER BY rank
      LIMIT ?
      """

      {:ok, %{rows: rows, columns: columns}} =
        SQL.query(Repo, sql, [
          fts_query(query),
          agent_id,
          agent_id,
          search_opts.type,
          search_opts.type,
          search_opts.status,
          search_opts.status,
          search_opts.min_importance,
          search_opts.min_importance,
          limit
        ])

      rows
      |> Enum.map(&Enum.zip(columns, &1))
      |> Enum.map(&Map.new/1)
      |> Enum.map(&Repo.load(Entry, &1))
    rescue
      _ ->
        Entry
        |> maybe_filter_agent(agent_id)
        |> maybe_filter_type(search_opts.type)
        |> maybe_filter_status(search_opts.status)
        |> maybe_filter_min_importance(search_opts.min_importance)
        |> where([entry], like(entry.content, ^"%#{query}%"))
        |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
        |> limit(^limit)
        |> Repo.all()
    end
  end

  defp semantic_search(agent_id, query, limit, search_opts, query_context) do
    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(search_opts.type)
    |> maybe_filter_status(search_opts.status)
    |> maybe_filter_min_importance(search_opts.min_importance)
    |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
    |> limit(^max(limit * 4, 80))
    |> Repo.all()
    |> Enum.map(fn entry ->
      {entry, semantic_similarity(entry, query_context, query)}
    end)
    |> Enum.filter(fn {_entry, score} -> score > 0 end)
    |> Enum.sort_by(fn {entry, score} -> {-score, -entry.importance} end)
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 0))
  end

  defp query_terms(query) do
    query
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/u, trim: true)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
  end

  defp semantic_similarity(_entry, %{terms: []}, _query), do: 0.0

  defp semantic_similarity(entry, query_context, query) do
    query_terms = query_context.terms
    haystack_terms = semantic_terms(entry)

    overlap =
      MapSet.intersection(MapSet.new(query_terms), MapSet.new(haystack_terms))
      |> MapSet.size()

    if overlap == 0 do
      0.0
    else
      overlap / max(length(query_terms), 1) +
        provenance_semantic_boost(entry, query_terms) +
        type_semantic_boost(entry, query_terms) +
        channel_semantic_boost(entry, query_context.channels) +
        phrase_fragment_boost(entry, query)
    end
  end

  defp search_score_breakdown(entry, lexical_rank, semantic_rank, query_context, query) do
    %{
      "lexical" => round_score(reciprocal_rank(lexical_rank)),
      "semantic" => round_score(reciprocal_rank(semantic_rank)),
      "importance" => round_score(importance_boost(entry)),
      "recency" => round_score(recency_boost(entry)),
      "embedding" => round_score(vector_similarity(entry, query_context) * 0.18),
      "provenance" => round_score(provenance_boost(entry, query)),
      "type_intent" => round_score(type_intent_boost(entry, query)),
      "channel" => round_score(channel_context_boost(entry, query_context.channels)),
      "phrase" => round_score(exact_phrase_boost(entry, query))
    }
  end

  defp bulletin_score(entry) do
    importance_boost(entry) +
      recency_boost(entry) +
      bulletin_type_boost(entry) +
      bulletin_channel_boost(entry) +
      if(ingest_backed?(entry), do: 0.04, else: 0.0) +
      if(recently_reinforced?(entry), do: 0.03, else: 0.0) +
      if(entry.status == "conflicted", do: 0.02, else: 0.0)
  end

  defp reciprocal_rank(nil), do: 0.0
  defp reciprocal_rank(rank), do: 1.0 / (60 + rank)

  defp importance_boost(entry), do: entry.importance * 0.2

  defp recency_boost(%{updated_at: nil}), do: 0.0

  defp recency_boost(entry) do
    age_days = DateTime.diff(DateTime.utc_now(), entry.updated_at, :day)

    cond do
      age_days <= 1 -> 0.06
      age_days <= 7 -> 0.04
      age_days <= 30 -> 0.02
      true -> 0.0
    end
  end

  defp exact_phrase_boost(_entry, query) when query in [nil, ""], do: 0.0

  defp exact_phrase_boost(entry, query) do
    if String.contains?(String.downcase(entry.content || ""), String.downcase(query)),
      do: 0.08,
      else: 0.0
  end

  defp hybrid_reasons(entry, lexical_rank, semantic_rank, query_context, query) do
    []
    |> maybe_add_reason(not is_nil(lexical_rank), "lexical match")
    |> maybe_add_reason(not is_nil(semantic_rank), "semantic overlap")
    |> maybe_add_reason(entry.importance >= 0.8, importance_reason(entry))
    |> maybe_add_reason(entry.status == "conflicted", "unresolved conflict")
    |> maybe_add_reason(ingest_backed?(entry), "ingest provenance")
    |> maybe_add_reason(type_intent_boost(entry, query) > 0, type_reason(entry))
    |> maybe_add_reason(
      channel_context_boost(entry, query_context.channels) > 0,
      "channel context"
    )
    |> maybe_add_reason(provenance_boost(entry, query) > 0, "source provenance")
    |> maybe_add_reason(vector_similarity(entry, query_context) >= 0.2, "embedding similarity")
    |> maybe_add_reason(recently_reinforced?(entry), "recently reinforced")
    |> maybe_add_reason(
      is_binary(query) and query != "" and exact_phrase_boost(entry, query) > 0,
      "exact phrase"
    )
  end

  defp importance_reason(entry) do
    cond do
      entry.importance >= 0.9 -> "high importance"
      entry.importance >= 0.7 -> "important memory"
      true -> "memory match"
    end
  end

  defp type_reason(%{type: "Goal"}), do: "goal match"
  defp type_reason(%{type: "Todo"}), do: "todo match"
  defp type_reason(%{type: "Decision"}), do: "decision match"
  defp type_reason(%{type: "Preference"}), do: "preference match"
  defp type_reason(_entry), do: "typed memory match"

  defp bulletin_type_reason(%{type: "Goal"}), do: "goal memory"
  defp bulletin_type_reason(%{type: "Todo"}), do: "todo memory"
  defp bulletin_type_reason(%{type: "Decision"}), do: "decision memory"
  defp bulletin_type_reason(%{type: "Preference"}), do: "preference memory"
  defp bulletin_type_reason(%{type: "Identity"}), do: "identity memory"
  defp bulletin_type_reason(_entry), do: "relevant memory"

  defp maybe_add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  defp lexical_rank_order(nil), do: 9_999
  defp lexical_rank_order(rank), do: rank

  defp round_score(score), do: Float.round(score, 4)

  defp enrich_memory_attrs(attrs, entry \\ nil) do
    attrs = normalize_attr_map(attrs)

    metadata =
      enriched_memory_metadata(Map.get(attrs, "metadata") || entry_metadata(entry), attrs, entry)

    Map.put(attrs, "metadata", metadata)
  end

  defp enriched_memory_metadata(metadata, attrs, entry \\ nil) do
    metadata = metadata || %{}
    content = Map.get(attrs, "content") || entry_value(entry, :content) || ""
    type = Map.get(attrs, "type") || entry_value(entry, :type)
    status = Map.get(attrs, "status") || entry_value(entry, :status) || "active"

    semantic_terms =
      [
        type,
        content,
        metadata["source_file"],
        metadata["source_section"],
        metadata["source_channel"],
        metadata["conflict_reason"]
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" ")
      |> query_terms()
      |> Enum.take(24)

    {:ok, embedding} = Embeddings.embed([type, content | semantic_terms])

    metadata
    |> Map.put("semantic_terms", semantic_terms)
    |> Map.put("semantic_vector", build_semantic_vector(semantic_terms))
    |> Map.put("embedding_backend", embedding.backend)
    |> Map.put("embedding_model", embedding.model)
    |> Map.put("embedding_dimensions", embedding.dimensions)
    |> Map.put("embedding_vector", embedding.vector)
    |> Map.put("embedding_generated_at", DateTime.utc_now())
    |> maybe_put("embedding_fallback_from", Map.get(embedding, :fallback_from))
    |> maybe_put("embedding_fallback_reason", Map.get(embedding, :fallback_reason))
    |> Map.put("recall_type", type)
    |> Map.put("recall_status", status)
  end

  defp normalize_attr_map(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp semantic_terms(entry) do
    persisted =
      entry.metadata
      |> Kernel.||(%{})
      |> Map.get("semantic_terms", [])
      |> List.wrap()

    if persisted == [] do
      [
        entry.type,
        entry.content,
        get_in(entry.metadata || %{}, ["source_file"]),
        get_in(entry.metadata || %{}, ["source_section"]),
        get_in(entry.metadata || %{}, ["source_channel"]),
        get_in(entry.metadata || %{}, ["conflict_reason"])
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> query_terms()
    else
      persisted
    end
  end

  defp semantic_vector(entry) do
    entry.metadata
    |> Kernel.||(%{})
    |> Map.get("semantic_vector")
    |> case do
      value when is_map(value) and map_size(value) > 0 -> value
      _value -> build_semantic_vector(semantic_terms(entry))
    end
  end

  defp embedding_vector(entry) do
    case get_in(entry.metadata || %{}, ["embedding_vector"]) do
      vector when is_list(vector) and vector != [] -> vector
      _ -> []
    end
  end

  defp embedded_memory?(metadata) when is_map(metadata) do
    case metadata["embedding_vector"] do
      vector when is_list(vector) and vector != [] -> true
      _ -> false
    end
  end

  defp embedded_memory?(_metadata), do: false

  defp stale_embedding?(metadata, runtime_status) when is_map(metadata) do
    embedded_memory?(metadata) and
      (metadata["embedding_backend"] != runtime_status.active_backend or
         metadata["embedding_model"] != runtime_status.active_model)
  end

  defp stale_embedding?(_metadata, _runtime_status), do: false

  defp provenance_boost(_entry, query) when query in [nil, ""], do: 0.0

  defp provenance_boost(entry, query) do
    terms = query_terms(query)

    source_terms =
      [
        get_in(entry.metadata || %{}, ["source_file"]),
        get_in(entry.metadata || %{}, ["source_section"])
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" ")
      |> query_terms()

    if source_terms != [] and
         MapSet.intersection(MapSet.new(terms), MapSet.new(source_terms)) |> MapSet.size() > 0 do
      0.05
    else
      0.0
    end
  end

  defp provenance_semantic_boost(entry, terms) do
    source_terms =
      [
        get_in(entry.metadata || %{}, ["source_file"]),
        get_in(entry.metadata || %{}, ["source_section"])
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" ")
      |> query_terms()

    overlap = MapSet.intersection(MapSet.new(terms), MapSet.new(source_terms)) |> MapSet.size()
    if overlap > 0, do: 0.08, else: 0.0
  end

  defp type_intent_boost(_entry, query) when query in [nil, ""], do: 0.0

  defp type_intent_boost(entry, query) do
    type_semantic_boost(entry, query_terms(query))
  end

  defp type_semantic_boost(entry, query_terms) do
    wanted =
      case entry.type do
        "Goal" -> ["goal", "plan", "target"]
        "Todo" -> ["todo", "task", "next"]
        "Decision" -> ["decision", "decided", "policy"]
        "Preference" -> ["prefer", "preference", "likes"]
        "Identity" -> ["identity", "about", "who"]
        _ -> []
      end

    if wanted != [] and Enum.any?(wanted, &(&1 in query_terms)), do: 0.05, else: 0.0
  end

  defp phrase_fragment_boost(_entry, query) when query in [nil, ""], do: 0.0

  defp phrase_fragment_boost(entry, query) do
    content = String.downcase(entry.content || "")

    fragments =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(&Enum.join(&1, " "))

    if Enum.any?(fragments, &(String.length(&1) > 4 and String.contains?(content, &1))),
      do: 0.03,
      else: 0.0
  end

  defp vector_similarity(_entry, %{terms: [], embedding: []}), do: 0.0
  defp vector_similarity(_entry, query) when query in [nil, ""], do: 0.0

  defp vector_similarity(entry, %{embedding: embedding, terms: terms})
       when is_list(embedding) and embedding != [] do
    case embedding_vector(entry) do
      [] ->
        left = semantic_vector(entry)
        right = build_semantic_vector(terms)
        do_vector_similarity(left, right)

      left ->
        Embeddings.cosine_similarity(left, embedding)
    end
  end

  defp vector_similarity(entry, %{terms: terms}) do
    left = semantic_vector(entry)
    right = build_semantic_vector(terms)
    do_vector_similarity(left, right)
  end

  defp vector_similarity(entry, query) do
    left = semantic_vector(entry)
    right = query |> query_terms() |> build_semantic_vector()

    do_vector_similarity(left, right)
  end

  defp do_vector_similarity(left, right) do
    if map_size(left) == 0 or map_size(right) == 0 do
      0.0
    else
      shared_terms =
        left
        |> Map.keys()
        |> Enum.filter(&Map.has_key?(right, &1))

      Enum.reduce(shared_terms, 0.0, fn term, acc ->
        acc + Map.get(left, term, 0.0) * Map.get(right, term, 0.0)
      end)
    end
  end

  defp build_semantic_vector(terms) do
    terms
    |> List.wrap()
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.frequencies()
    |> normalize_vector()
  end

  defp normalize_vector(frequencies) do
    magnitude =
      frequencies
      |> Map.values()
      |> Enum.reduce(0.0, fn value, acc -> acc + value * value end)
      |> :math.sqrt()

    if magnitude == 0.0 do
      %{}
    else
      Map.new(frequencies, fn {term, value} -> {term, Float.round(value / magnitude, 6)} end)
    end
  end

  defp ingest_backed?(entry), do: get_in(entry.metadata || %{}, ["source"]) == "ingest"

  defp build_query_context(query) do
    terms = query_terms(query)
    {:ok, embedding} = Embeddings.embed(terms)

    %{
      terms: terms,
      embedding: embedding.vector,
      channels:
        terms
        |> Enum.filter(
          &(&1 in ~w(telegram discord slack webchat cli scheduler control plane control_plane))
        )
        |> Enum.map(fn
          "control" -> "control_plane"
          "plane" -> "control_plane"
          other -> other
        end)
        |> Enum.uniq()
    }
  end

  defp channel_context_boost(_entry, []), do: 0.0

  defp channel_context_boost(entry, channels) do
    if memory_channel(entry) in channels, do: 0.06, else: 0.0
  end

  defp bulletin_reasons(entry) do
    []
    |> maybe_add_reason(true, bulletin_type_reason(entry))
    |> maybe_add_reason(entry.importance >= 0.7, importance_reason(entry))
    |> maybe_add_reason(ingest_backed?(entry), "ingest provenance")
    |> maybe_add_reason(recently_reinforced?(entry), "recently reinforced")
    |> maybe_add_reason(not is_nil(memory_channel(entry)), "channel context")
  end

  defp bulletin_type_boost(%{type: "Goal"}), do: 0.15
  defp bulletin_type_boost(%{type: "Todo"}), do: 0.13
  defp bulletin_type_boost(%{type: "Decision"}), do: 0.11
  defp bulletin_type_boost(%{type: "Preference"}), do: 0.09
  defp bulletin_type_boost(%{type: "Identity"}), do: 0.07
  defp bulletin_type_boost(%{type: "Event"}), do: 0.04
  defp bulletin_type_boost(%{type: "Observation"}), do: 0.03
  defp bulletin_type_boost(_entry), do: 0.0

  defp bulletin_channel_boost(entry) do
    if memory_channel(entry), do: 0.04, else: 0.0
  end

  defp channel_semantic_boost(_entry, []), do: 0.0

  defp channel_semantic_boost(entry, channels) do
    if memory_channel(entry) in channels, do: 0.08, else: 0.0
  end

  defp memory_channel(entry) do
    get_in(entry.metadata || %{}, ["source_channel"]) ||
      if(Ecto.assoc_loaded?(entry.conversation), do: entry.conversation.channel, else: nil)
  end

  defp recently_reinforced?(entry) do
    timestamp = entry.last_seen_at || entry.updated_at
    timestamp && DateTime.diff(DateTime.utc_now(), timestamp, :day) <= 3
  end

  defp increment_count(counts, nil), do: counts
  defp increment_count(counts, ""), do: counts
  defp increment_count(counts, key), do: Map.update(counts, key, 1, &(&1 + 1))

  defp normalize_datetime(%DateTime{} = value), do: value

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp max_timestamp(nil, timestamp), do: timestamp
  defp max_timestamp(timestamp, nil), do: timestamp

  defp max_timestamp(left, right) do
    if DateTime.compare(left, right) == :lt, do: right, else: left
  end

  defp entry_metadata(nil), do: %{}
  defp entry_metadata(entry), do: entry.metadata || %{}

  defp entry_value(nil, _field), do: nil
  defp entry_value(entry, field), do: Map.get(entry, field)

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, error}), do: {:error, error}
end
