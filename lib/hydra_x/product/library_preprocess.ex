defmodule HydraX.Product.LibraryPreprocess do
  @moduledoc """
  Library spec §4 preprocessing pipeline.

  Runs after a source is created and chunked. Each stage's output is
  persisted before the next runs, so a partial failure leaves usable
  artifacts. Stages 1+2 (parse, chunk+embed) already happen during
  `Product.create_source/2`; this module owns stages 3-8.

    * Stage 3 — source-level summary (~100-150 words)
    * Stage 4 — topic extraction with semantic match-or-create
    * Stage 5 — citation extraction (academic, best-effort)
    * Stage 6 — author + publication match-or-create
    * Stage 7 — contradiction check across sources sharing topics
    * Stage 8 — completion (`ingestion_status = processed | partial`)

  `enqueue/1` runs the pipeline asynchronously under the TaskSupervisor.
  `run_stage/2` re-triggers a single stage (for the source-detail
  re-run UI per spec §4.3).
  """

  require Logger
  import Ecto.Query

  alias HydraX.Embeddings
  alias HydraX.Graph.Flags
  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Graph.Nodes
  alias HydraX.Graph.Relationships
  alias HydraX.LLM.Router, as: LLM
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Repo

  @stages ~w(summary topics citations authors_publications contradictions)a
  @topic_similarity_threshold 0.82
  @summary_target_words 125

  @doc """
  Run the full preprocessing pipeline asynchronously. Safe to call after
  `Product.create_source/2`.
  """
  def enqueue(%GraphNode{type_key: "source"} = source) do
    {:ok, _pid} =
      Task.Supervisor.start_child(HydraX.TaskSupervisor, fn -> run(source) end)

    {:ok, source}
  end

  @doc """
  Run all stages synchronously. Returns the final source.
  """
  def run(%GraphNode{type_key: "source"} = source) do
    source = mark(source, %{"ingestion_status" => "processing"})

    {final_source, failures} =
      Enum.reduce(@stages, {source, []}, fn stage, {current, fails} ->
        case run_stage_safe(current, stage) do
          {:ok, updated} -> {updated, fails}
          {:error, reason} -> {current, [{stage, reason} | fails]}
        end
      end)

    finalize(final_source, Enum.reverse(failures))
  end

  @doc """
  Re-run a single stage (spec §4.3 — user re-triggers from source detail).
  """
  def run_stage(%GraphNode{type_key: "source"} = source, stage)
      when stage in @stages do
    run_stage_safe(source, stage)
  end

  def run_stage(_, stage), do: {:error, {:unknown_stage, stage}}

  # -----------------------------------------------------------------
  # Pipeline
  # -----------------------------------------------------------------

  defp run_stage_safe(source, stage) do
    try do
      do_run_stage(source, stage)
    rescue
      err ->
        Logger.warning(
          "[LibraryPreprocess] stage=#{stage} source=#{source.id} raised: #{inspect(err)}"
        )

        {:error, :exception}
    end
  end

  defp do_run_stage(source, :summary), do: stage_summary(source)
  defp do_run_stage(source, :topics), do: stage_topics(source)
  defp do_run_stage(source, :citations), do: stage_citations(source)
  defp do_run_stage(source, :authors_publications), do: stage_authors_publications(source)
  defp do_run_stage(source, :contradictions), do: stage_contradictions(source)

  # -----------------------------------------------------------------
  # Stage 3 — summary
  # -----------------------------------------------------------------

  defp stage_summary(source) do
    text = body_excerpt(source, 6000)

    if text == "" do
      {:error, :empty_body}
    else
      messages = [
        %{role: "system", content: summary_system_prompt()},
        %{role: "user", content: "Summarise this source:\n\n#{text}"}
      ]

      case LLM.complete(%{
             messages: messages,
             process_type: "library_preprocess",
             max_tokens: 400
           }) do
        {:ok, response} ->
          summary =
            response
            |> get_content()
            |> String.trim()

          updated =
            mark(source, %{
              "ingestion_summary" => summary
            })

          # Mirror summary into source body for graph display, but keep
          # original parsed text accessible via source_chunks.
          updated = update_body_to_summary(updated, summary)

          {:ok, updated}

        {:error, reason} ->
          {:error, {:llm_error, reason}}
      end
    end
  end

  defp summary_system_prompt do
    """
    You write tight 100-150 word summaries of source documents for a research library.
    The summary captures the core claim, the evidence/argument shape, and what
    domain the source belongs to. Plain prose. No bullets, no headings.
    Target: about #{@summary_target_words} words. Hard cap: 180 words.
    Respond with the summary text only.
    """
  end

  defp update_body_to_summary(source, summary) when is_binary(summary) and summary != "" do
    case source
         |> GraphNode.changeset(%{body: summary})
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> source
    end
  end

  defp update_body_to_summary(source, _), do: source

  # -----------------------------------------------------------------
  # Stage 4 — topics (semantic match-or-create)
  # -----------------------------------------------------------------

  defp stage_topics(source) do
    text = body_excerpt(source, 5000)

    case extract_topic_candidates(source, text) do
      {:ok, []} ->
        {:ok, source}

      {:ok, candidates} ->
        existing = list_existing_topics(source.project_id)

        Enum.each(candidates, fn cand ->
          link_or_create_topic(source, cand, existing)
        end)

        {:ok, source}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_topic_candidates(source, "") do
    # Fallback for empty body — derive single coarse topic from title
    {:ok, [%{"name" => source.title, "granularity" => "coarse", "description" => "", "weight" => 0.5}]}
  end

  defp extract_topic_candidates(_source, text) do
    messages = [
      %{role: "system", content: topic_system_prompt()},
      %{role: "user", content: "Extract topics for this source:\n\n#{text}"}
    ]

    case LLM.complete(%{
           messages: messages,
           process_type: "library_preprocess",
           max_tokens: 600
         }) do
      {:ok, response} ->
        {:ok, parse_topic_response(get_content(response))}

      {:error, reason} ->
        {:error, {:llm_error, reason}}
    end
  end

  defp topic_system_prompt do
    """
    You identify the topics a research source is about. Topics are concepts
    or themes — not titles, not file types. Granularity:
      "coarse"  — broad fields (e.g., "cognitive science", "organic chemistry")
      "medium"  — specific subfields (e.g., "working memory", "Diels-Alder reaction")
      "fine"    — narrow methods or phenomena (e.g., "n-back paradigm")

    Return at most 5 topics. Each topic includes a short description (1 sentence).
    Weight 0.0-1.0 encodes prominence in this source.

    Respond ONLY with a JSON object of this shape:
    {"topics": [
      {"name": "...", "granularity": "coarse|medium|fine",
       "description": "...", "weight": 0.0-1.0}
    ]}
    """
  end

  defp parse_topic_response(content) do
    case Jason.decode(content || "") do
      {:ok, %{"topics" => topics}} when is_list(topics) ->
        topics
        |> Enum.filter(fn t -> is_map(t) and is_binary(t["name"]) and t["name"] != "" end)
        |> Enum.take(5)

      _ ->
        []
    end
  end

  defp link_or_create_topic(source, candidate, existing_topics) do
    name = candidate["name"]
    granularity = candidate["granularity"] || "medium"
    description = candidate["description"] || ""
    weight = candidate["weight"] || 0.5

    case best_topic_match(name, description, existing_topics) do
      {:ok, %GraphNode{} = topic} ->
        link_topic(source, topic, weight)

      :no_match ->
        case create_topic(source.project_id, name, description, granularity) do
          {:ok, topic} -> link_topic(source, topic, weight)
          _ -> :ok
        end
    end
  end

  defp best_topic_match(_name, _description, []), do: :no_match

  defp best_topic_match(name, description, existing) do
    target_text = "#{name}. #{description}"

    case Embeddings.embed(target_text) do
      {:ok, %{vector: target}} when is_list(target) ->
        scored =
          existing
          |> Enum.map(fn topic ->
            topic_text =
              "#{topic.title}. #{Map.get(topic.attributes || %{}, "description", "")}"

            score =
              case Embeddings.embed(topic_text) do
                {:ok, %{vector: v}} when is_list(v) ->
                  Embeddings.cosine_similarity(target, v)

                _ ->
                  0.0
              end

            {topic, score}
          end)
          |> Enum.sort_by(fn {_, s} -> s end, :desc)

        case scored do
          [{topic, score} | _] when score >= @topic_similarity_threshold ->
            {:ok, topic}

          _ ->
            # Fall back to case-insensitive exact name match
            name_match =
              Enum.find(existing, fn t ->
                String.downcase(t.title || "") == String.downcase(name || "")
              end)

            if name_match, do: {:ok, name_match}, else: :no_match
        end

      _ ->
        :no_match
    end
  end

  defp create_topic(project_id, name, description, granularity) do
    Nodes.create_node(project_id, %{
      type_key: "topic",
      title: name,
      status: "active",
      attributes: %{
        "granularity" => granularity,
        "description" => description,
        "aliases" => []
      }
    })
  end

  defp link_topic(source, topic, weight) do
    Relationships.create_relationship(source, topic, "is_about",
      weight: clamp_weight(weight),
      attributes: %{}
    )
    |> case do
      {:ok, _edge} -> :ok
      # Idempotent — duplicate is fine
      {:error, _} -> :ok
    end
  end

  defp list_existing_topics(project_id) do
    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "topic" and is_nil(n.archived_at)
    )
    |> Repo.all()
  end

  # -----------------------------------------------------------------
  # Stage 5 — citation extraction (academic best-effort)
  # -----------------------------------------------------------------

  defp stage_citations(source) do
    case detect_references_section(source.body || "") do
      nil ->
        # Non-academic — skip per spec §4.2
        {:ok, source}

      refs_block ->
        cited_works = parse_reference_lines(refs_block)

        # Per spec §4.2: record metadata, do NOT create ghost nodes in V1.
        # Cross-reference against existing Library sources for `cites` edges.
        existing_sources = list_existing_sources(source.project_id, source.id)

        Enum.each(cited_works, fn ref_text ->
          case find_matching_source(ref_text, existing_sources) do
            nil ->
              :ok

            %GraphNode{} = match ->
              Relationships.create_relationship(source, match, "cites", weight: 1.0)
          end
        end)

        updated =
          mark(source, %{
            "cited_works_count" => length(cited_works),
            "cited_works_unmatched" =>
              length(cited_works) -
                Enum.count(cited_works, &find_matching_source(&1, existing_sources))
          })

        {:ok, updated}
    end
  end

  # Heuristic: find a "References" / "Bibliography" / "Works Cited" section
  # near the end of the body. Returns the substring after the heading or nil.
  defp detect_references_section(body) when is_binary(body) and body != "" do
    pattern = ~r/\n\s*(?:References|Bibliography|Works\s+Cited)\s*\n/i

    case Regex.split(pattern, body, parts: 2) do
      [_pre, refs] when byte_size(refs) > 50 -> refs
      _ -> nil
    end
  end

  defp detect_references_section(_), do: nil

  defp parse_reference_lines(refs_block) do
    refs_block
    |> String.split(~r/\n(?=\s*\[\d+\]|\s*\d+\.)|\n{2,}/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or byte_size(&1) > 800))
    |> Enum.take(200)
  end

  defp list_existing_sources(project_id, exclude_id) do
    from(n in GraphNode,
      where:
        n.project_id == ^project_id and n.type_key == "source" and
          n.id != ^exclude_id and is_nil(n.archived_at)
    )
    |> Repo.all()
  end

  defp find_matching_source(ref_text, existing_sources) do
    ref_lc = String.downcase(ref_text)

    Enum.find(existing_sources, fn s ->
      title = String.downcase(s.title || "")
      title != "" and String.contains?(ref_lc, title)
    end)
  end

  # -----------------------------------------------------------------
  # Stage 6 — author + publication
  # -----------------------------------------------------------------

  defp stage_authors_publications(source) do
    text = body_excerpt(source, 4000)

    case extract_authors_publications(text) do
      {:ok, %{authors: authors, publications: publications}} ->
        Enum.each(authors, &link_or_create_author(source, &1))
        Enum.each(publications, &link_or_create_publication(source, &1))
        {:ok, source}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_authors_publications("") do
    {:ok, %{authors: [], publications: []}}
  end

  defp extract_authors_publications(text) do
    messages = [
      %{role: "system", content: authors_system_prompt()},
      %{role: "user", content: "Extract metadata from this source:\n\n#{text}"}
    ]

    case LLM.complete(%{
           messages: messages,
           process_type: "library_preprocess",
           max_tokens: 400
         }) do
      {:ok, response} ->
        {:ok, parse_authors_response(get_content(response))}

      {:error, reason} ->
        {:error, {:llm_error, reason}}
    end
  end

  defp authors_system_prompt do
    """
    Extract bibliographic metadata from the source. Return ONLY what is
    explicitly present in the text — do NOT guess or fabricate.

    Respond ONLY with this JSON shape:
    {
      "authors": [{"display_name": "...", "disambiguator": "..."}],
      "publications": [{"name": "...", "kind": "journal|conference|book|magazine|blog|news|report|other"}]
    }

    If unknown, return empty arrays.
    """
  end

  defp parse_authors_response(content) do
    case Jason.decode(content || "") do
      {:ok, %{"authors" => a, "publications" => p}} when is_list(a) and is_list(p) ->
        %{
          authors: Enum.filter(a, &valid_named_entry?(&1, "display_name")),
          publications: Enum.filter(p, &valid_named_entry?(&1, "name"))
        }

      _ ->
        %{authors: [], publications: []}
    end
  end

  defp valid_named_entry?(entry, key) do
    is_map(entry) and is_binary(entry[key]) and entry[key] != ""
  end

  defp link_or_create_author(source, %{"display_name" => name} = entry) do
    disambiguator = entry["disambiguator"] || ""

    case find_entity_by_title(source.project_id, "author", name) do
      %GraphNode{} = author ->
        Relationships.create_relationship(source, author, "authored_by", weight: 1.0)

      nil ->
        case Nodes.create_node(source.project_id, %{
               type_key: "author",
               title: name,
               status: "active",
               attributes: %{
                 "display_name" => name,
                 "disambiguator" => disambiguator,
                 "external_identifiers" => %{}
               }
             }) do
          {:ok, author} ->
            Relationships.create_relationship(source, author, "authored_by", weight: 1.0)

          _ ->
            :ok
        end
    end
  end

  defp link_or_create_publication(source, %{"name" => name} = entry) do
    kind = entry["kind"] || "other"

    case find_entity_by_title(source.project_id, "publication", name) do
      %GraphNode{} = pub ->
        Relationships.create_relationship(source, pub, "published_in", weight: 1.0)

      nil ->
        case Nodes.create_node(source.project_id, %{
               type_key: "publication",
               title: name,
               status: "active",
               attributes: %{"name" => name, "kind" => kind}
             }) do
          {:ok, pub} ->
            Relationships.create_relationship(source, pub, "published_in", weight: 1.0)

          _ ->
            :ok
        end
    end
  end

  defp find_entity_by_title(project_id, type_key, title) do
    title_lc = String.downcase(title || "")

    from(n in GraphNode,
      where:
        n.project_id == ^project_id and n.type_key == ^type_key and
          fragment("LOWER(?) = ?", n.title, ^title_lc)
    )
    |> Repo.one()
  end

  # -----------------------------------------------------------------
  # Stage 7 — contradiction check across sources sharing topics
  # -----------------------------------------------------------------

  defp stage_contradictions(source) do
    siblings = sibling_sources_via_shared_topics(source)

    Enum.each(siblings, fn sibling ->
      maybe_flag_contradiction(source, sibling)
    end)

    {:ok, source}
  end

  defp sibling_sources_via_shared_topics(source) do
    # Find topics this source is about
    topic_ids =
      from(r in HydraX.Graph.NodeRelationship,
        where:
          r.project_id == ^source.project_id and
            r.from_node_id == ^source.id and
            r.from_node_type == "source" and
            r.type_key == "is_about",
        select: r.to_node_id
      )
      |> Repo.all()

    if topic_ids == [] do
      []
    else
      # Find other sources is_about any of these topics
      sibling_ids =
        from(r in HydraX.Graph.NodeRelationship,
          where:
            r.project_id == ^source.project_id and
              r.to_node_id in ^topic_ids and
              r.type_key == "is_about" and
              r.from_node_type == "source" and
              r.from_node_id != ^source.id,
          select: r.from_node_id,
          distinct: true
        )
        |> Repo.all()

      from(n in GraphNode,
        where: n.id in ^sibling_ids and n.type_key == "source" and is_nil(n.archived_at)
      )
      |> Repo.all()
    end
  end

  defp maybe_flag_contradiction(source, sibling) do
    # Conservative V1: emit a `needs_review` flag (not auto `contradicts`)
    # when summaries diverge significantly. This avoids false-positives
    # while still surfacing the conflict to the user.
    a = (source.attributes["ingestion_summary"] || source.body || "") |> String.slice(0, 600)
    b = (sibling.attributes["ingestion_summary"] || sibling.body || "") |> String.slice(0, 600)

    if a != "" and b != "" and likely_disagreement?(a, b) do
      Flags.raise_flag(source, "needs_review",
        detected_by_agent_id: "library_preprocess",
        detection_context: %{
          "kind" => "possible_contradiction",
          "sibling_source_id" => sibling.id,
          "sibling_title" => sibling.title
        }
      )
    end

    :ok
  end

  # Cheap heuristic: low cosine similarity on summary embeddings indicates
  # disagreement. Real disagreement detection is a V1.1 tuning problem.
  defp likely_disagreement?(a, b) do
    with {:ok, %{vector: va}} when is_list(va) <- Embeddings.embed(a),
         {:ok, %{vector: vb}} when is_list(vb) <- Embeddings.embed(b) do
      Embeddings.cosine_similarity(va, vb) < 0.35
    else
      _ -> false
    end
  end

  # -----------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------

  defp finalize(source, []) do
    updated =
      mark(source, %{
        "ingestion_status" => "processed",
        "ingestion_failures" => []
      })
      |> set_status("completed")

    broadcast(updated, "library.preprocess.completed")
    updated
  end

  defp finalize(source, failures) do
    failure_names = Enum.map(failures, fn {stage, _} -> to_string(stage) end)
    all_failed = length(failures) == length(@stages)

    status = if all_failed, do: "failed", else: "partial"

    updated =
      mark(source, %{
        "ingestion_status" => status,
        "ingestion_failures" => failure_names
      })
      |> set_status(if all_failed, do: "failed", else: "completed")

    broadcast(updated, "library.preprocess.partial")
    updated
  end

  defp mark(%GraphNode{} = source, updates) when is_map(updates) do
    merged = Map.merge(source.attributes || %{}, updates)

    case source
         |> GraphNode.changeset(%{attributes: merged})
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> source
    end
  end

  defp set_status(%GraphNode{} = source, status) do
    case source
         |> GraphNode.changeset(%{status: status})
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> source
    end
  end

  defp body_excerpt(%GraphNode{body: body}, max) when is_binary(body) do
    String.slice(body, 0, max)
  end

  defp body_excerpt(_, _), do: ""

  defp get_content(response) when is_map(response) do
    response[:content] || response["content"] || ""
  end

  defp get_content(_), do: ""

  defp clamp_weight(w) when is_number(w), do: max(0.0, min(1.0, w * 1.0))
  defp clamp_weight(_), do: 0.5

  defp broadcast(%GraphNode{} = source, event) do
    ProductPubSub.broadcast_project_event(source.project_id, event, %{
      source_id: source.id,
      ingestion_status: Map.get(source.attributes || %{}, "ingestion_status"),
      ingestion_failures: Map.get(source.attributes || %{}, "ingestion_failures", [])
    })
  end

  @doc """
  Public list of stage names (for re-trigger UI).
  """
  def stages, do: @stages
end
