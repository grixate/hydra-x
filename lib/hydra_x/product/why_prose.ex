defmodule HydraX.Product.WhyProse do
  @moduledoc """
  Why-button prose generation + caching. Cycle 1 hero feature.

  Flow:
    1. Resolve lineage upstream from the target node via `Product.Graph`
    2. Synthesize a Vision card from `Project.description` (real Vision
       schema lands in Cycle 2 — the spec's "no Vision set" edge case
       gracefully handles an empty description).
    3. Compute cache key = sha256(project_description + lineage chain IDs
       + lineage content). Look up `why_prose_cache`.
    4. On miss, build a prompt per spec §4 and call the Strategist via
       `HydraX.LLM.Router.complete/1` (synchronous one-shot for Cycle 1;
       streaming is Cycle 2 polish). Store the prose and return.
  """

  require Logger

  alias HydraX.LLM.Router, as: LLM
  alias HydraX.Product.Graph
  alias HydraX.Product.Project
  alias HydraX.Product.WhyProseCache
  alias HydraX.Repo

  @type lineage_node :: %{
          node_type: String.t(),
          node_id: integer() | nil,
          title: String.t(),
          body: String.t(),
          status: String.t() | nil,
          is_vision: boolean(),
          is_target: boolean(),
          edge_kind: String.t() | nil,
          stale: boolean(),
          updated_at: DateTime.t() | nil
        }

  @max_prose_words 150
  @prose_max_tokens 400

  @doc """
  Return the full Why-button payload for a node, generating prose if needed.

  Returns:
    {:ok, %{lineage: [...], prose: string | nil, vision_present: bool,
            orphan: bool, cached: bool, error: string | nil}}
    {:error, :not_found}
  """
  def build(project_id, node_type, node_id, opts \\ []) do
    project = Repo.get(Project, to_int(project_id))
    if is_nil(project), do: throw(:not_found)

    case Graph.resolve_node(node_type, to_int(node_id)) do
      {:ok, nil} ->
        {:error, :not_found}

      {:error, _} ->
        {:error, :not_found}

      {:ok, target_record} ->
        raw_lineage = build_lineage(project, node_type, target_record, node_id)
        lineage = mark_stale(raw_lineage)
        vision_present = lineage_has_vision?(lineage)
        orphan = lineage_is_orphan?(lineage)
        contradictions = contradictions_for_target(node_type, node_id)

        prose_result =
          if Keyword.get(opts, :skip_prose, false) do
            {:ok, nil, false}
          else
            fetch_or_generate_prose(project, node_type, node_id, lineage, opts)
          end

        case prose_result do
          {:ok, prose, cached} ->
            {:ok,
             %{
               lineage: lineage,
               prose: prose,
               vision_present: vision_present,
               orphan: orphan,
               cached: cached,
               error: nil,
               contradictions: contradictions
             }}

          {:error, reason} ->
            {:ok,
             %{
               lineage: lineage,
               prose: nil,
               vision_present: vision_present,
               orphan: orphan,
               cached: false,
               error: humanize_error(reason),
               contradictions: contradictions
             }}
        end
    end
  catch
    :not_found -> {:error, :not_found}
  end

  ## Lineage construction

  defp build_lineage(%Project{} = project, node_type, target_record, node_id) do
    node_id_int = to_int(node_id)

    upstream = Graph.trace_upstream(project.id, node_type, node_id_int, max_depth: 8)

    # Deepest-first from `Graph.trace_upstream` — reverse so Vision-ish
    # sits at the top of the chain and the target at the bottom.
    ancestor_cards =
      upstream
      |> Enum.reverse()
      |> resolve_ancestor_cards(project)

    target_card = target_card(target_record, node_type, node_id_int)

    vision_card_or_nil = vision_card(project)

    cards =
      (if(vision_card_or_nil, do: [vision_card_or_nil], else: [])) ++ ancestor_cards ++ [target_card]

    cards
  end

  defp resolve_ancestor_cards(ancestor_refs, _project) do
    refs = Enum.map(ancestor_refs, fn n -> {n.node_type, n.node_id} end)

    resolved =
      Graph.resolve_nodes(refs)
      |> Map.new(fn {type, id, record} -> {{type, id}, record} end)

    Enum.map(ancestor_refs, fn n ->
      record = Map.get(resolved, {to_string(n.node_type), n.node_id})

      %{
        node_type: to_string(n.node_type),
        node_id: n.node_id,
        title: record && Map.get(record, :title) || "(unknown)",
        body: record |> resolve_body() |> truncate(240),
        status: record && Map.get(record, :status) || nil,
        is_vision: false,
        is_target: false,
        edge_kind: n.edge_kind && to_string(n.edge_kind),
        updated_at: record && Map.get(record, :updated_at)
      }
    end)
  end

  defp target_card(record, node_type, node_id) do
    %{
      node_type: to_string(node_type),
      node_id: node_id,
      title: Map.get(record, :title) || "(untitled)",
      body: record |> resolve_body() |> truncate(240),
      status: Map.get(record, :status),
      is_vision: false,
      is_target: true,
      edge_kind: nil,
      updated_at: Map.get(record, :updated_at)
    }
  end

  # Prefer the real Vision node (Stream A0.1) over the synthesized
  # fallback from `project.description`.
  defp vision_card(%Project{} = project) do
    case HydraX.Product.Visions.get_for_project(project.id) do
      %HydraX.Product.Vision{} = v ->
        %{
          node_type: "vision",
          node_id: v.id,
          title: v.title,
          body: truncate(v.body || "", 280),
          status: v.status,
          is_vision: true,
          is_target: false,
          edge_kind: nil,
          updated_at: v.updated_at
        }

      nil ->
        fallback_vision_card(project)
    end
  end

  defp fallback_vision_card(%Project{description: desc} = project)
       when is_binary(desc) and desc != "" do
    %{
      node_type: "vision",
      node_id: nil,
      title: project.name,
      body: truncate(desc, 280),
      status: nil,
      is_vision: true,
      is_target: false,
      edge_kind: nil,
      updated_at: project.updated_at
    }
  end

  defp fallback_vision_card(_), do: nil

  # Stream B2.3 — mark any ancestor card stale when its `updated_at` is
  # newer than the target's. A downstream card cannot have been informed
  # by an ancestor update that happened after it was created.
  defp mark_stale(lineage) do
    target = Enum.find(lineage, & &1.is_target)
    target_anchor = target && target[:updated_at]

    Enum.map(lineage, fn card ->
      card_ts = card[:updated_at]

      stale? =
        cond do
          card.is_target ->
            false

          is_nil(card_ts) or is_nil(target_anchor) ->
            false

          not is_struct(card_ts, DateTime) or not is_struct(target_anchor, DateTime) ->
            false

          true ->
            DateTime.compare(card_ts, target_anchor) == :gt
        end

      Map.put(card, :stale, stale?)
    end)
  end

  defp contradictions_for_target(node_type, node_id) do
    HydraX.Coherence.list_for_node(node_type, node_id)
    |> Enum.map(fn c ->
      %{
        id: c.id,
        severity: c.severity,
        explanation: c.explanation,
        status: c.status,
        mode: c.mode
      }
    end)
  rescue
    _ -> []
  end

  defp lineage_has_vision?(lineage), do: Enum.any?(lineage, & &1.is_vision)

  defp lineage_is_orphan?(lineage) do
    # Only the target card is present — no ancestors, no Vision.
    Enum.count(lineage) == 1 and
      Enum.any?(lineage, & &1.is_target)
  end

  ## Cache + generation

  defp fetch_or_generate_prose(project, node_type, node_id, lineage, opts) do
    key = cache_key(project, lineage)

    if Keyword.get(opts, :force_regenerate, false) do
      do_generate_and_store(project, node_type, node_id, lineage, key)
    else
      case Repo.get_by(WhyProseCache,
             project_id: project.id,
             node_type: to_string(node_type),
             node_id: to_int(node_id),
             cache_key: key
           ) do
        nil -> do_generate_and_store(project, node_type, node_id, lineage, key)
        %WhyProseCache{prose: prose} -> {:ok, prose, true}
      end
    end
  end

  defp do_generate_and_store(project, node_type, node_id, lineage, key) do
    case generate_prose(project, lineage) do
      {:ok, prose, model_id} ->
        attrs = %{
          project_id: project.id,
          node_type: to_string(node_type),
          node_id: to_int(node_id),
          cache_key: key,
          prose: prose,
          model_id: model_id,
          generated_at: DateTime.utc_now()
        }

        # On unique-conflict (concurrent generate), upsert.
        case %WhyProseCache{}
             |> WhyProseCache.changeset(attrs)
             |> Repo.insert(
               on_conflict: {:replace, [:prose, :model_id, :generated_at]},
               conflict_target: [:project_id, :node_type, :node_id, :cache_key]
             ) do
          {:ok, _} -> {:ok, prose, false}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp cache_key(%Project{} = project, lineage) do
    payload =
      :erlang.term_to_binary({
        to_string(project.description || ""),
        Enum.map(lineage, fn card ->
          {card.node_type, card.node_id, card.title, card.body, card.is_vision, card.is_target}
        end)
      })

    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  end

  ## Prose generation via Strategist

  defp generate_prose(%Project{} = project, lineage) do
    strategist_agent_id = project.strategist_agent_id

    request = %{
      agent_id: strategist_agent_id,
      process_type: "why_button",
      messages: [
        %{role: "system", content: system_prompt()},
        %{role: "user", content: user_prompt(project, lineage)}
      ],
      max_tokens: @prose_max_tokens,
      temperature: 0.5
    }

    case LLM.complete(request) do
      {:ok, %{content: content} = response} when is_binary(content) and content != "" ->
        model_id = Map.get(response, :model) || Map.get(response, :model_id)
        {:ok, trim_prose(content), to_string_or_nil(model_id)}

      {:ok, _} ->
        {:error, :empty_response}

      {:error, _} = err ->
        err
    end
  rescue
    err ->
      Logger.warning("[WhyProse] generation raised: #{inspect(err)}")
      {:error, :exception}
  end

  defp system_prompt do
    """
    You are generating a "why" explanation for a node in a product graph.
    Walk from the Vision node down to the target node, following the
    lineage chain. For each step, explain in one sentence why the next
    node exists given the previous one. Use causal language ("because",
    "which led to", "in response to", "from that").

    Keep the full explanation under #{@max_prose_words} words.
    End with a single-sentence summary in this format:
    "So <target title> exists because <root reason>."

    Rules:
    - Use only the actual chain provided. Do not invent nodes or reasoning.
    - If the chain has no Vision, say so honestly and suggest connecting it.
    - Avoid meta-language ("the lineage shows…") and filler.
    - Avoid generic platitudes ("this supports the broader vision of…").
    - Use the user's own words from node content where possible.
    - Solo/personal tone is fine — you may address the user directly.
    """
  end

  defp user_prompt(%Project{} = project, lineage) do
    chain_rendered =
      lineage
      |> Enum.map_join("\n\n", &render_card_for_prompt/1)

    target = Enum.find(lineage, & &1.is_target) || List.last(lineage)

    vision_line =
      case Enum.find(lineage, & &1.is_vision) do
        nil -> "VISION: (not yet set for this project)"
        v -> "VISION: #{v.title} — #{v.body}"
      end

    """
    PROJECT: #{project.name}
    #{vision_line}

    LINEAGE CHAIN (top → bottom):
    #{chain_rendered}

    TARGET NODE: #{target.node_type} — #{target.title}

    Generate the prose explanation now.
    """
  end

  defp render_card_for_prompt(card) do
    header =
      cond do
        card.is_vision -> "VISION — #{card.title}"
        card.is_target -> "TARGET #{String.upcase(card.node_type)} — #{card.title}"
        true -> "#{String.upcase(card.node_type)} — #{card.title}"
      end

    body = card.body || ""
    "- #{header}\n  #{String.slice(body, 0, 240)}"
  end

  defp trim_prose(content) do
    content
    |> String.trim()
    |> cap_word_count(@max_prose_words + 30)
  end

  defp cap_word_count(text, max_words) do
    words = String.split(text, ~r/\s+/, trim: true)

    if length(words) <= max_words do
      text
    else
      Enum.take(words, max_words) |> Enum.join(" ") |> Kernel.<>("…")
    end
  end

  defp humanize_error(:empty_response), do: "The Strategist returned no content."
  defp humanize_error(:exception), do: "Unexpected error while generating prose."
  defp humanize_error(:no_provider_configured), do: "No LLM provider is configured."
  defp humanize_error(reason) when is_atom(reason), do: "Generation failed: #{reason}."
  defp humanize_error(_), do: "Generation failed."

  defp resolve_body(nil), do: ""

  defp resolve_body(record) do
    Map.get(record, :body) ||
      Map.get(record, :content) ||
      Map.get(record, :description) ||
      ""
  end

  defp truncate(nil, _), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) <= n, do: text, else: String.slice(text, 0, n - 1) <> "…"
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v), do: to_string(v)
end
