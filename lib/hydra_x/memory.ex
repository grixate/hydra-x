defmodule HydraX.Memory do
  @moduledoc """
  Typed graph memory storage with lexical search and markdown export.
  """

  import Ecto.Query

  alias HydraX.Embeddings
  alias HydraX.Memory.{Edge, Entry, EvidenceRecord, Markdown, Routing}
  alias HydraX.Product
  alias HydraX.Repo
  alias HydraX.Runtime

  def get_memory!(id), do: Repo.get!(Entry, id)

  def get_evidence!(id), do: Repo.get!(EvidenceRecord, id)

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
    statuses = Keyword.get(opts, :statuses)
    min_importance = Keyword.get(opts, :min_importance)
    scope_kind = Keyword.get(opts, :scope_kind)
    scope_key = Keyword.get(opts, :scope_key)
    hall = Keyword.get(opts, :hall)
    topic_key = Keyword.get(opts, :topic_key)
    as_of = Keyword.get(opts, :as_of)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(type)
    |> maybe_filter_status(status)
    |> maybe_filter_statuses(statuses)
    |> maybe_filter_min_importance(min_importance)
    |> maybe_filter_scope_kind(scope_kind)
    |> maybe_filter_scope_key(scope_key)
    |> maybe_filter_hall(hall)
    |> maybe_filter_topic_key(topic_key)
    |> maybe_filter_as_of(as_of)
    |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
    |> preload([:conversation, :evidence_records])
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def list_evidence(opts \\ []) do
    memory_id = Keyword.get(opts, :memory_id)
    product_node_type = Keyword.get(opts, :product_node_type)
    product_node_id = Keyword.get(opts, :product_node_id)
    limit = Keyword.get(opts, :limit, 50)

    EvidenceRecord
    |> maybe_filter_memory_id(memory_id)
    |> maybe_filter_product_ref(product_node_type, product_node_id)
    |> order_by([record], desc: record.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def embedding_status(agent_id \\ nil) do
    embedding_runtime = Embeddings.status()

    entries =
      Entry
      |> maybe_filter_agent(agent_id)
      |> Repo.all()

    {embedded_count, unembedded_count, stale_count, fallback_count, backend_counts, model_counts,
     last_generated_at} =
      Enum.reduce(entries, {0, 0, 0, 0, %{}, %{}, nil}, fn entry,
                                                           {embedded, unembedded, stale, fallback,
                                                            backends, models, last_generated} ->
        metadata = entry.metadata || %{}
        embedded? = embedded_memory?(entry)
        backend = metadata["embedding_backend"]
        model = metadata["embedding_model"]
        fallback_from = metadata["embedding_fallback_from"]
        generated_at = metadata["embedding_generated_at"]

        {
          embedded + if(embedded?, do: 1, else: 0),
          unembedded + if(embedded?, do: 0, else: 1),
          stale + if(stale_embedding?(entry, embedding_runtime), do: 1, else: 0),
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

    query_context = %{
      query_context
      | scope_key: search_opts.scope_key || query_context.scope_key,
        topic_key: search_opts.topic_key || query_context.topic_key,
        hall: search_opts.hall || query_context.hall
    }

    candidate_limit = max(limit * 4, 20)

    lexical_results = staged_lexical_search(agent_id, query, candidate_limit, search_opts)

    semantic_results =
      staged_semantic_search(agent_id, query, candidate_limit, search_opts, query_context)

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

      evidence = evidence_snapshot(entry)
      related = maybe_related_topic_snapshot(entry, search_opts)

      %{
        entry: entry,
        score: score_breakdown |> Map.values() |> Enum.sum() |> round_score(),
        vector_score: round_score(vector_score),
        lexical_rank: lexical_rank,
        semantic_rank: semantic_rank,
        score_breakdown: score_breakdown,
        reasons: hybrid_reasons(entry, lexical_rank, semantic_rank, query_context, query),
        evidence: evidence,
        related: related
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
          do: Map.put(search_opts, :statuses, ["active", "durable"]),
          else: search_opts
      end)

    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(search_opts.type)
    |> maybe_filter_status(search_opts[:status])
    |> maybe_filter_statuses(search_opts[:statuses])
    |> maybe_filter_min_importance(search_opts.min_importance)
    |> maybe_filter_scope_kind(search_opts.scope_kind)
    |> maybe_filter_scope_key(search_opts.scope_key)
    |> maybe_filter_hall(search_opts.hall)
    |> maybe_filter_topic_key(search_opts.topic_key)
    |> maybe_filter_as_of(search_opts.as_of)
    |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
    |> limit(^max(limit * 4, 48))
    |> Repo.all()
    |> Enum.map(fn entry ->
      score_breakdown = bulletin_score_breakdown(entry)

      %{
        entry: entry,
        score: score_breakdown |> Map.values() |> Enum.sum() |> round_score(),
        reasons: bulletin_reasons(entry),
        score_breakdown: score_breakdown
      }
    end)
    |> Enum.sort_by(&{-&1.score, -&1.entry.importance})
    |> Enum.take(limit)
  end

  def wake_up(agent_id, opts \\ []) do
    agent = Runtime.get_agent!(agent_id)
    scope_key = Keyword.get(opts, :scope_key)
    topic_key = Keyword.get(opts, :topic_key)
    conversation = Keyword.get(opts, :conversation)

    project_id =
      Keyword.get(opts, :project_id) ||
        get_in((conversation && conversation.metadata) || %{}, ["product_project_id"])

    l0_identity = %{
      name: agent.name,
      slug: agent.slug,
      role: agent.role,
      description: agent.description
    }

    l1_ranked =
      bulletin_ranked(agent_id, 10,
        statuses: ["active", "durable"],
        scope_key: scope_key
      )

    l2_ranked =
      if scope_key || topic_key do
        search_ranked(agent_id, topic_key || scope_key || agent.slug, 6,
          statuses: ["active", "durable"],
          scope_key: scope_key,
          topic_key: topic_key
        )
      else
        []
      end

    product_nodes =
      case parse_integer(project_id) do
        nil -> []
        project_id -> Product.related_memory_projection(project_id, topic_key, scope_key, 6)
      end

    %{
      l0_identity: l0_identity,
      l1_essential: Enum.map(l1_ranked, &wake_up_ranked_snapshot/1),
      l2_scoped: Enum.map(l2_ranked, &wake_up_ranked_snapshot/1),
      compact_text:
        render_wake_up_packet(
          l0_identity,
          Enum.map(l1_ranked, &wake_up_ranked_snapshot/1),
          Enum.map(l2_ranked, &wake_up_ranked_snapshot/1),
          product_nodes
        ),
      sources: %{
        memory_ids: Enum.map(l1_ranked ++ l2_ranked, & &1.entry.id) |> Enum.uniq(),
        evidence_ids:
          Enum.flat_map(l1_ranked ++ l2_ranked, fn ranked ->
            Enum.map(Map.get(ranked, :evidence, []), & &1.id)
          end)
          |> Enum.uniq(),
        product_nodes: product_nodes
      }
    }
  end

  def compact_context(agent_id, opts \\ []) do
    packet = wake_up(agent_id, opts)

    %{
      scope_key: Keyword.get(opts, :scope_key),
      topic_key: Keyword.get(opts, :topic_key),
      wake_up_packet: packet,
      compact_text: packet.compact_text,
      supporting_memories: packet.l2_scoped ++ packet.l1_essential,
      supporting_evidence:
        packet.sources.evidence_ids
        |> Enum.map(&get_evidence!/1)
        |> Enum.map(&evidence_record_snapshot/1)
    }
  end

  def review_conversation_checkpoint(conversation_id, opts \\ []) do
    conversation = Runtime.get_conversation!(conversation_id)
    turns = Runtime.list_turns(conversation_id)
    transcript = Enum.map_join(Enum.take(turns, -12), "\n", &"#{&1.role}: #{&1.content}")
    scope_key = "conversation:#{conversation.id}"
    topic_key = Routing.topic_key([conversation.title, transcript])

    packet =
      compact_context(conversation.agent_id,
        scope_key: scope_key,
        topic_key: topic_key,
        conversation: conversation
      )

    recent_user_turns =
      turns
      |> Enum.filter(&(&1.role == "user"))
      |> Enum.take(-6)
      |> Enum.map(fn turn ->
        %{turn_id: turn.id, excerpt: String.slice(turn.content || "", 0, 180)}
      end)

    payload = %{
      "review_reason" => Keyword.get(opts, :reason, "checkpoint"),
      "scope_key" => scope_key,
      "topic_key" => topic_key,
      "wake_up_packet" => packet,
      "recent_user_turns" => recent_user_turns,
      "updated_at" => DateTime.utc_now()
    }

    case Runtime.upsert_checkpoint(conversation_id, "memory_review", payload) do
      {:ok, checkpoint} -> checkpoint
      other -> other
    end
  end

  def create_diary_entry(agent_id, content, opts \\ []) do
    create_memory(%{
      agent_id: agent_id,
      type: Keyword.get(opts, :type, "Observation"),
      content: content,
      importance: Keyword.get(opts, :importance, 0.65),
      conversation_id: Keyword.get(opts, :conversation_id),
      metadata:
        %{}
        |> Map.put("diary_topic", Keyword.get(opts, :topic, "general"))
        |> Map.put("source", "diary")
        |> maybe_put("source_channel", Keyword.get(opts, :source_channel)),
      hall: "diary",
      scope_kind: "agent",
      scope_key: "agent:#{agent_id}",
      topic_key: Routing.topic_key(Keyword.get(opts, :topic, "general")),
      last_seen_at: DateTime.utc_now()
    })
  end

  def attach_evidence(attrs) when is_map(attrs) do
    %EvidenceRecord{}
    |> EvidenceRecord.changeset(normalize_attr_map(attrs))
    |> Repo.insert()
  end

  def create_memory(attrs) do
    attrs = enrich_memory_attrs(attrs)

    Repo.transaction(fn ->
      entry =
        %Entry{}
        |> Entry.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, entry} -> entry
          {:error, changeset} -> Repo.rollback(changeset)
        end

      attach_runtime_evidence!(entry, attrs)
      maybe_flag_conflict_candidate(entry)
      Repo.preload(entry, [:conversation, :evidence_records])
    end)
    |> unwrap_transaction()
    |> case do
      {:ok, entry} ->
        maybe_refresh_cortex(entry.agent_id)
        broadcast_memory(entry.agent_id)
        {:ok, entry}

      error ->
        error
    end
  end

  def change_memory(entry \\ %Entry{}, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end

  def update_memory(%Entry{} = entry, attrs) do
    attrs = enrich_memory_attrs(attrs, entry)

    Repo.transaction(fn ->
      updated =
        entry
        |> Entry.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end

      attach_runtime_evidence!(updated, attrs)
      maybe_flag_conflict_candidate(updated)
      Repo.preload(updated, [:conversation, :evidence_records])
    end)
    |> unwrap_transaction()
    |> case do
      {:ok, updated} ->
        maybe_refresh_cortex(updated.agent_id)
        broadcast_memory(updated.agent_id)
        {:ok, updated}

      error ->
        error
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
              |> then(fn metadata ->
                enriched_memory_metadata(
                  %{
                    content: target_content,
                    type: target.type,
                    status: target.status,
                    importance: target.importance,
                    scope_kind: target.scope_kind,
                    scope_key: target.scope_key,
                    hall: target.hall,
                    topic_key: target.topic_key,
                    valid_from: target.valid_from,
                    valid_to: target.valid_to
                  },
                  metadata
                )
              end)
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
              |> then(fn metadata ->
                enriched_memory_metadata(
                  %{
                    content: winner_content,
                    type: winner.type,
                    status: "active",
                    importance: winner.importance,
                    scope_kind: winner.scope_kind,
                    scope_key: winner.scope_key,
                    hall: winner.hall,
                    topic_key: winner.topic_key,
                    valid_from: winner.valid_from,
                    valid_to: winner.valid_to
                  },
                  metadata
                )
              end)
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
    list_memories(agent_id: agent_id, limit: 500, statuses: ["active", "durable"])
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

  defp maybe_filter_scope_kind(query, nil), do: query
  defp maybe_filter_scope_kind(query, ""), do: query

  defp maybe_filter_scope_kind(query, scope_kind),
    do: where(query, [entry], entry.scope_kind == ^scope_kind)

  defp maybe_filter_scope_key(query, nil), do: query
  defp maybe_filter_scope_key(query, ""), do: query

  defp maybe_filter_scope_key(query, scope_key),
    do: where(query, [entry], entry.scope_key == ^scope_key)

  defp maybe_filter_hall(query, nil), do: query
  defp maybe_filter_hall(query, ""), do: query
  defp maybe_filter_hall(query, hall), do: where(query, [entry], entry.hall == ^hall)

  defp maybe_filter_topic_key(query, nil), do: query
  defp maybe_filter_topic_key(query, ""), do: query

  defp maybe_filter_topic_key(query, topic_key),
    do: where(query, [entry], entry.topic_key == ^topic_key)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, "all"), do: query
  defp maybe_filter_status(query, status), do: where(query, [entry], entry.status == ^status)

  defp maybe_filter_statuses(query, nil), do: query
  defp maybe_filter_statuses(query, []), do: query

  defp maybe_filter_statuses(query, statuses) when is_list(statuses),
    do: where(query, [entry], entry.status in ^statuses)

  defp maybe_filter_min_importance(query, nil), do: query

  defp maybe_filter_min_importance(query, min_importance),
    do: where(query, [entry], entry.importance >= ^min_importance)

  defp maybe_filter_as_of(query, nil), do: query
  defp maybe_filter_as_of(query, ""), do: query

  defp maybe_filter_as_of(query, as_of) do
    case Routing.parse_datetime(as_of) do
      nil ->
        query

      parsed_as_of ->
        where(
          query,
          [entry],
          (is_nil(entry.valid_from) or entry.valid_from <= ^parsed_as_of) and
            (is_nil(entry.valid_to) or entry.valid_to >= ^parsed_as_of)
        )
    end
  end

  defp maybe_filter_memory_id(query, nil), do: query

  defp maybe_filter_memory_id(query, memory_id),
    do: where(query, [record], record.memory_id == ^memory_id)

  defp maybe_filter_product_ref(query, nil, _node_id), do: query
  defp maybe_filter_product_ref(query, _node_type, nil), do: query

  defp maybe_filter_product_ref(query, node_type, node_id) do
    where(
      query,
      [record],
      record.product_node_type == ^to_string(node_type) and record.product_node_id == ^node_id
    )
  end

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

  defp search_opts(opts) do
    %{
      type: Keyword.get(opts, :type),
      status: Keyword.get(opts, :status),
      statuses: Keyword.get(opts, :statuses),
      min_importance: Keyword.get(opts, :min_importance),
      scope_kind: Keyword.get(opts, :scope_kind),
      scope_key: Keyword.get(opts, :scope_key),
      hall: Keyword.get(opts, :hall),
      topic_key: Keyword.get(opts, :topic_key),
      as_of: Keyword.get(opts, :as_of),
      include_related: Keyword.get(opts, :include_related, false)
    }
  end

  defp staged_lexical_search(agent_id, query, limit, search_opts) do
    stage_opts(search_opts)
    |> Enum.flat_map(fn stage ->
      lexical_search(agent_id, query, limit, Map.merge(search_opts, stage))
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(limit)
  end

  defp staged_semantic_search(agent_id, query, limit, search_opts, query_context) do
    stage_opts(search_opts)
    |> Enum.flat_map(fn stage ->
      semantic_search(agent_id, query, limit, Map.merge(search_opts, stage), query_context)
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(limit)
  end

  defp stage_opts(search_opts) do
    [
      %{scope_key: search_opts.scope_key, topic_key: search_opts.topic_key, hall: nil},
      %{scope_key: search_opts.scope_key, topic_key: nil, hall: search_opts.hall},
      %{scope_key: search_opts.scope_key, topic_key: nil, hall: nil},
      %{scope_key: nil, topic_key: nil, hall: nil}
    ]
    |> Enum.uniq()
  end

  defp lexical_search(agent_id, query, limit, search_opts) do
    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(search_opts.type)
    |> maybe_filter_status(search_opts.status)
    |> maybe_filter_statuses(search_opts.statuses)
    |> maybe_filter_min_importance(search_opts.min_importance)
    |> maybe_filter_scope_kind(search_opts.scope_kind)
    |> maybe_filter_scope_key(search_opts.scope_key)
    |> maybe_filter_hall(search_opts.hall)
    |> maybe_filter_topic_key(search_opts.topic_key)
    |> maybe_filter_as_of(search_opts.as_of)
    |> where(
      [_entry],
      fragment("search_vector @@ websearch_to_tsquery('english', ?)", ^query)
    )
    |> order_by(
      [entry],
      desc: fragment("ts_rank_cd(search_vector, websearch_to_tsquery('english', ?))", ^query),
      desc: entry.importance,
      desc: entry.updated_at
    )
    |> limit(^limit)
    |> Repo.all()
  rescue
    _ ->
      Entry
      |> maybe_filter_agent(agent_id)
      |> maybe_filter_type(search_opts.type)
      |> maybe_filter_status(search_opts.status)
      |> maybe_filter_statuses(search_opts.statuses)
      |> maybe_filter_min_importance(search_opts.min_importance)
      |> maybe_filter_scope_kind(search_opts.scope_kind)
      |> maybe_filter_scope_key(search_opts.scope_key)
      |> maybe_filter_hall(search_opts.hall)
      |> maybe_filter_topic_key(search_opts.topic_key)
      |> maybe_filter_as_of(search_opts.as_of)
      |> where([entry], like(entry.content, ^"%#{query}%"))
      |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
      |> limit(^limit)
      |> Repo.all()
  end

  defp semantic_search(agent_id, query, limit, search_opts, query_context) do
    Entry
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_type(search_opts.type)
    |> maybe_filter_status(search_opts.status)
    |> maybe_filter_statuses(search_opts.statuses)
    |> maybe_filter_min_importance(search_opts.min_importance)
    |> maybe_filter_scope_kind(search_opts.scope_kind)
    |> maybe_filter_scope_key(search_opts.scope_key)
    |> maybe_filter_hall(search_opts.hall)
    |> maybe_filter_topic_key(search_opts.topic_key)
    |> maybe_filter_as_of(search_opts.as_of)
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
      "phrase" => round_score(exact_phrase_boost(entry, query)),
      "scope" => round_score(scope_boost(entry, query_context)),
      "topic" => round_score(topic_boost(entry, query_context)),
      "hall" => round_score(hall_boost(entry, query_context)),
      "temporal" => round_score(temporal_boost(entry, query))
    }
  end

  defp bulletin_score_breakdown(entry) do
    %{
      "importance" => round_score(importance_boost(entry)),
      "recency" => round_score(recency_boost(entry)),
      "type_intent" => round_score(bulletin_type_boost(entry)),
      "channel" => round_score(bulletin_channel_boost(entry)),
      "provenance" => round_score(if(ingest_backed?(entry), do: 0.04, else: 0.0)),
      "reinforcement" => round_score(if(recently_reinforced?(entry), do: 0.03, else: 0.0)),
      "status" => round_score(if(entry.status == "conflicted", do: 0.02, else: 0.0))
    }
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
    |> maybe_add_reason(scope_boost(entry, query_context) > 0, "scope routing")
    |> maybe_add_reason(topic_boost(entry, query_context) > 0, "topic routing")
    |> maybe_add_reason(hall_boost(entry, query_context) > 0, "hall routing")
    |> maybe_add_reason(temporal_boost(entry, query) > 0, "temporal fit")
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

  defp evidence_snapshot(entry) do
    list_evidence(memory_id: entry.id, limit: 3)
    |> Enum.map(&evidence_record_snapshot/1)
  end

  defp evidence_record_snapshot(record) do
    %{
      id: record.id,
      source_kind: record.source_kind,
      source_ref: record.source_ref,
      excerpt: record.excerpt,
      speaker_role: record.speaker_role,
      occurred_at: record.occurred_at,
      metadata: record.metadata || %{}
    }
  end

  defp maybe_related_topic_snapshot(entry, %{include_related: true}) do
    related_topic_snapshot(entry)
  end

  defp maybe_related_topic_snapshot(_entry, _search_opts), do: []

  def related_topic_snapshot(%Entry{} = entry) do
    if entry.topic_key in [nil, ""] do
      []
    else
      list_memories(
        agent_id: entry.agent_id,
        topic_key: entry.topic_key,
        statuses: ["active", "durable", "conflicted"],
        limit: 6
      )
      |> Enum.reject(&(&1.id == entry.id))
      |> Enum.map(fn related ->
        %{
          id: related.id,
          type: related.type,
          hall: related.hall,
          scope_key: related.scope_key,
          content: related.content
        }
      end)
    end
  end

  defp wake_up_ranked_snapshot(ranked) do
    %{
      id: ranked.entry.id,
      type: ranked.entry.type,
      hall: ranked.entry.hall,
      scope_key: ranked.entry.scope_key,
      topic_key: ranked.entry.topic_key,
      content: ranked.entry.content,
      score: ranked.score,
      reasons: ranked.reasons,
      evidence: Map.get(ranked, :evidence, [])
    }
  end

  defp render_wake_up_packet(identity, l1, l2, product_nodes) do
    identity_line =
      [
        "name=#{identity.name}",
        "slug=#{identity.slug}",
        "role=#{identity.role}",
        identity.description && "desc=#{identity.description}"
      ]
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.join(" | ")

    essential =
      Enum.map_join(l1, "\n", fn item ->
        "- [#{item.type}/#{item.hall || "facts"}] #{String.slice(item.content || "", 0, 180)}"
      end)

    scoped =
      Enum.map_join(l2, "\n", fn item ->
        "- [#{item.scope_key || "global"}] #{String.slice(item.content || "", 0, 180)}"
      end)

    product =
      Enum.map_join(product_nodes, "\n", fn node ->
        "- [#{node.node_type}] #{node.title}"
      end)

    [
      "## Wake-Up Packet",
      "### L0 Identity\n#{identity_line}",
      "### L1 Essential\n" <> if(essential == "", do: "- none", else: essential),
      "### L2 Scoped\n" <> if(scoped == "", do: "- none", else: scoped),
      "### Product Context\n" <> if(product == "", do: "- none", else: product)
    ]
    |> Enum.join("\n\n")
  end

  defp attach_runtime_evidence!(entry, attrs) do
    evidence_items =
      runtime_evidence_candidates(entry, attrs)
      |> Enum.uniq_by(fn item -> {item["source_kind"], item["source_ref"], item["excerpt"]} end)

    Enum.each(evidence_items, fn evidence_attrs ->
      attrs =
        evidence_attrs
        |> Map.put("memory_id", entry.id)
        |> Map.put_new("occurred_at", DateTime.utc_now())

      %EvidenceRecord{}
      |> EvidenceRecord.changeset(attrs)
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:memory_id, :source_kind, :source_ref, :excerpt]
      )
    end)
  end

  defp runtime_evidence_candidates(entry, attrs) do
    metadata = Map.get(attrs, "metadata", %{})

    direct =
      case Map.get(attrs, "evidence") do
        values when is_list(values) ->
          Enum.map(values, fn item ->
            item
            |> normalize_attr_map()
            |> Map.put_new(
              "excerpt",
              Map.get(item, "excerpt") || Map.get(item, :excerpt) || entry.content
            )
          end)

        _ ->
          []
      end

    conversation_excerpt =
      if entry.conversation_id do
        [
          %{
            "source_kind" => "conversation_turn",
            "source_ref" => "conversation:#{entry.conversation_id}",
            "excerpt" => String.slice(entry.content || "", 0, 240),
            "speaker_role" => "agent"
          }
        ]
      else
        []
      end

    ingest_excerpt =
      if metadata["source"] == "ingest" do
        [
          %{
            "source_kind" => "ingest",
            "source_ref" => metadata["source_file"] || metadata["source_section"] || "ingest",
            "excerpt" => String.slice(entry.content || "", 0, 240),
            "speaker_role" => nil
          }
        ]
      else
        []
      end

    direct ++ conversation_excerpt ++ ingest_excerpt
  end

  defp maybe_flag_conflict_candidate(entry) do
    if (entry.status in ["active", "durable"] and entry.scope_key) && entry.topic_key &&
         entry.hall do
      Entry
      |> where(
        [other],
        other.id != ^entry.id and other.agent_id == ^entry.agent_id and
          other.status in ["active", "durable"] and
          other.scope_key == ^entry.scope_key and other.topic_key == ^entry.topic_key and
          other.hall == ^entry.hall
      )
      |> Repo.all()
      |> Enum.filter(&Routing.temporal_overlap?(entry, &1))
      |> Enum.each(fn other ->
        if similar_conflict_candidate?(entry, other) do
          HydraX.Safety.log_event(%{
            agent_id: entry.agent_id,
            conversation_id: entry.conversation_id || other.conversation_id,
            category: "memory",
            level: "warn",
            message: "Conflict candidate detected for #{entry.scope_key}/#{entry.topic_key}",
            metadata: %{
              "source_id" => entry.id,
              "target_id" => other.id,
              "scope_key" => entry.scope_key,
              "topic_key" => entry.topic_key,
              "hall" => entry.hall
            }
          })
        end
      end)
    end
  end

  defp similar_conflict_candidate?(left, right) do
    left.content != right.content and left.type == right.type
  end

  defp enrich_memory_attrs(attrs, entry \\ nil) do
    attrs = normalize_attr_map(attrs)
    metadata = Map.get(attrs, "metadata") || entry_metadata(entry)
    scope_kind = Routing.runtime_scope_kind(attrs, entry)
    scope_key = Routing.runtime_scope_key(attrs, entry)
    hall = Routing.runtime_hall(attrs, entry)
    topic_key = Routing.runtime_topic_key(attrs, entry)

    valid_from =
      Routing.parse_datetime(
        Map.get(attrs, "valid_from") || get_in(metadata, ["valid_from"]) ||
          entry_value(entry, :valid_from)
      )

    valid_to =
      Routing.parse_datetime(
        Map.get(attrs, "valid_to") || get_in(metadata, ["valid_to"]) ||
          entry_value(entry, :valid_to)
      )

    attrs
    |> Map.put("scope_kind", scope_kind)
    |> Map.put("scope_key", scope_key)
    |> Map.put("hall", hall)
    |> Map.put("topic_key", topic_key)
    |> maybe_put("valid_from", valid_from)
    |> maybe_put("valid_to", valid_to)
    |> enriched_memory_metadata(metadata, entry)
  end

  defp enriched_memory_metadata(attrs, metadata, entry \\ nil) do
    metadata = metadata || %{}
    content = Map.get(attrs, "content") || entry_value(entry, :content) || ""
    type = Map.get(attrs, "type") || entry_value(entry, :type)
    status = Map.get(attrs, "status") || entry_value(entry, :status) || "active"
    scope_kind = Map.get(attrs, "scope_kind") || entry_value(entry, :scope_kind)
    scope_key = Map.get(attrs, "scope_key") || entry_value(entry, :scope_key)
    hall = Map.get(attrs, "hall") || entry_value(entry, :hall)
    topic_key = Map.get(attrs, "topic_key") || entry_value(entry, :topic_key)
    valid_from = Map.get(attrs, "valid_from") || entry_value(entry, :valid_from)
    valid_to = Map.get(attrs, "valid_to") || entry_value(entry, :valid_to)

    semantic_terms =
      [
        type,
        content,
        scope_kind,
        scope_key,
        hall,
        topic_key,
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

    attrs
    |> Map.put("embedding", embedding.vector)
    |> Map.put(
      "metadata",
      metadata
      |> maybe_put("scope_kind", scope_kind)
      |> maybe_put("scope_key", scope_key)
      |> maybe_put("hall", hall)
      |> maybe_put("topic_key", topic_key)
      |> maybe_put("valid_from", valid_from && DateTime.to_iso8601(valid_from))
      |> maybe_put("valid_to", valid_to && DateTime.to_iso8601(valid_to))
      |> Map.put("semantic_terms", semantic_terms)
      |> Map.put("semantic_vector", build_semantic_vector(semantic_terms))
      |> Map.put("embedding_backend", embedding.backend)
      |> Map.put("embedding_model", embedding.model)
      |> Map.put("embedding_dimensions", embedding.dimensions)
      |> Map.put("embedding_generated_at", DateTime.utc_now())
      |> maybe_put("embedding_fallback_from", Map.get(embedding, :fallback_from))
      |> maybe_put("embedding_fallback_reason", Map.get(embedding, :fallback_reason))
      |> Map.put("recall_type", type)
      |> Map.put("recall_status", status)
    )
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
    case entry.embedding do
      %Pgvector{} = vector ->
        Pgvector.to_list(vector)

      vector when is_list(vector) and vector != [] ->
        vector

      _ ->
        case get_in(entry.metadata || %{}, ["embedding_vector"]) do
          vector when is_list(vector) and vector != [] -> vector
          _ -> []
        end
    end
  end

  defp embedded_memory?(%Entry{} = entry), do: embedding_vector(entry) != []
  defp embedded_memory?(_entry), do: false

  defp stale_embedding?(%Entry{} = entry, runtime_status) do
    metadata = entry.metadata || %{}

    embedded_memory?(entry) and
      (metadata["embedding_backend"] != runtime_status.active_backend or
         metadata["embedding_model"] != runtime_status.active_model)
  end

  defp stale_embedding?(_entry, _runtime_status), do: false

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

  defp scope_boost(entry, query_context) do
    case {entry.scope_key, query_context.scope_key} do
      {scope_key, scope_key} when is_binary(scope_key) and scope_key != "" -> 0.09
      _ -> 0.0
    end
  end

  defp topic_boost(entry, query_context) do
    case {entry.topic_key, query_context.topic_key} do
      {topic_key, topic_key} when is_binary(topic_key) and topic_key != "" -> 0.1
      _ -> 0.0
    end
  end

  defp hall_boost(entry, query_context) do
    case {entry.hall, query_context.hall} do
      {hall, hall} when is_binary(hall) and hall != "" -> 0.06
      _ -> 0.0
    end
  end

  defp temporal_boost(entry, query) do
    query = to_string(query || "")

    cond do
      query =~ ~r/\bas of\b/i and entry.valid_from -> 0.06
      query =~ ~r/\bcurrent\b|\bnow\b|\btoday\b/i and is_nil(entry.valid_to) -> 0.04
      query =~ ~r/\bprevious\b|\bformer\b|\bold\b/i and not is_nil(entry.valid_to) -> 0.04
      true -> 0.0
    end
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
      scope_key: infer_query_scope_key(query),
      topic_key: Routing.topic_key(query),
      hall: infer_query_hall(terms),
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

  defp infer_query_scope_key(query) do
    lowered = String.downcase(to_string(query || ""))

    cond do
      String.contains?(lowered, "project:") ->
        lowered
        |> String.split()
        |> Enum.find(&String.starts_with?(&1, "project:"))

      String.contains?(lowered, "conversation:") ->
        lowered
        |> String.split()
        |> Enum.find(&String.starts_with?(&1, "conversation:"))

      true ->
        nil
    end
  end

  defp infer_query_hall(terms) do
    cond do
      Enum.any?(terms, &(&1 in ~w(decision decided policy fact facts))) -> "facts"
      Enum.any?(terms, &(&1 in ~w(event timeline happened incident milestone))) -> "events"
      Enum.any?(terms, &(&1 in ~w(preference prefer style likes convention))) -> "preferences"
      Enum.any?(terms, &(&1 in ~w(goal todo task plan next advice))) -> "advice"
      Enum.any?(terms, &(&1 in ~w(discovery insight learning finding))) -> "discoveries"
      Enum.any?(terms, &(&1 in ~w(diary journal review note))) -> "diary"
      true -> nil
    end
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
    Routing.parse_datetime(value)
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

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, error}), do: {:error, error}
end
