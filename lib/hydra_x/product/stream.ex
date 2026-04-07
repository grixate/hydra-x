defmodule HydraX.Product.Stream do
  @moduledoc """
  Generates the personalized activity stream for a project.
  """

  import Ecto.Query

  alias HydraX.Product.Artifact
  alias HydraX.Product.Decision
  alias HydraX.Product.Graph
  alias HydraX.Product.GraphEdge
  alias HydraX.Product.GraphFlag
  alias HydraX.Product.Insight
  alias HydraX.Product.KnowledgeEntry
  alias HydraX.Product.Requirement
  alias HydraX.Product.SimulationNode
  alias HydraX.Repo

  @max_right_now 5

  # Time window (seconds) for grouping related items from the same agent
  @group_window_seconds 300

  def generate_stream(project_id, opts \\ []) do
    _role = Keyword.get(opts, :role, "founder")
    since = Keyword.get(opts, :since)

    right_now = generate_right_now(project_id)
    recently = generate_recently(project_id, since)
    emerging = generate_emerging(project_id)

    # Enrich all items with narratives
    right_now = Enum.map(right_now, &put_narrative(project_id, &1))
    recently = Enum.map(recently, &put_narrative(project_id, &1))
    emerging = Enum.map(emerging, &put_narrative(project_id, &1))

    # Group related items in the "recently" section
    recently = group_related_items(recently)

    %{
      right_now: Enum.take(right_now, @max_right_now),
      recently: recently,
      emerging: emerging
    }
  end

  # -------------------------------------------------------------------
  # Right now — action required
  # -------------------------------------------------------------------

  defp generate_right_now(project_id) do
    flag_items = flag_stream_items(project_id)
    draft_insight_items = draft_insight_stream_items(project_id)
    draft_decision_items = draft_decision_stream_items(project_id)
    draft_requirement_items = draft_requirement_stream_items(project_id)
    pending_knowledge_items = pending_knowledge_stream_items(project_id)
    proposed_simulation_items = proposed_simulation_stream_items(project_id)

    (flag_items ++
       draft_insight_items ++
       draft_decision_items ++
       draft_requirement_items ++ pending_knowledge_items ++ proposed_simulation_items)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp flag_stream_items(project_id) do
    GraphFlag
    |> where(
      [f],
      f.project_id == ^project_id and f.status == "open" and
        f.flag_type in ["needs_review", "contradicted"]
    )
    |> order_by([f], desc: f.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn flag ->
      node_title = resolve_node_title(flag.node_type, flag.node_id)
      connections = connection_counts(project_id, flag.node_type, flag.node_id)

      %{
        id: "flag-#{flag.id}",
        category: "flag",
        title: node_title || "#{flag.node_type}##{flag.node_id}",
        summary: flag.reason || "Review needed",
        node_type: flag.node_type,
        node_id: flag.node_id,
        urgency: "action",
        timestamp: flag.inserted_at,
        connections: connections,
        metadata: %{flag_id: flag.id, flag_type: flag.flag_type}
      }
    end)
  end

  defp draft_insight_stream_items(project_id) do
    Insight
    |> where([i], i.project_id == ^project_id and i.status == "draft")
    |> order_by([i], desc: i.inserted_at)
    |> limit(5)
    |> Repo.all()
    |> Enum.map(fn insight ->
      connections = connection_counts(project_id, "insight", insight.id)

      %{
        id: "insight-draft-#{insight.id}",
        category: "insight_created",
        title: insight.title,
        summary: String.slice(insight.body || "", 0, 200),
        node_type: "insight",
        node_id: insight.id,
        urgency: "action",
        timestamp: insight.inserted_at,
        connections: connections,
        metadata: %{status: "draft"}
      }
    end)
  end

  defp draft_decision_stream_items(project_id) do
    Decision
    |> where([d], d.project_id == ^project_id and d.status == "draft")
    |> order_by([d], desc: d.inserted_at)
    |> limit(5)
    |> Repo.all()
    |> Enum.map(fn decision ->
      connections = connection_counts(project_id, "decision", decision.id)

      %{
        id: "decision-draft-#{decision.id}",
        category: "decision_gate",
        title: decision.title,
        summary: String.slice(decision.body || "", 0, 200),
        node_type: "decision",
        node_id: decision.id,
        urgency: "action",
        timestamp: decision.inserted_at,
        connections: connections,
        metadata: %{status: "draft"}
      }
    end)
  end

  defp draft_requirement_stream_items(project_id) do
    Requirement
    |> where([r], r.project_id == ^project_id and r.status == "draft")
    |> order_by([r], desc: r.inserted_at)
    |> limit(5)
    |> Repo.all()
    |> Enum.map(fn req ->
      connections = connection_counts(project_id, "requirement", req.id)

      %{
        id: "requirement-draft-#{req.id}",
        category: "requirement_created",
        title: req.title,
        summary: String.slice(req.body || "", 0, 200),
        node_type: "requirement",
        node_id: req.id,
        urgency: "action",
        timestamp: req.inserted_at,
        connections: connections,
        metadata: %{status: "draft"}
      }
    end)
  end

  defp proposed_simulation_stream_items(project_id) do
    SimulationNode
    |> where([s], s.project_id == ^project_id and s.status == "proposed")
    |> order_by([s], desc: s.inserted_at)
    |> limit(3)
    |> Repo.all()
    |> Enum.map(fn sim ->
      metadata = sim.metadata || %{}

      %{
        id: "simulation-proposed-#{sim.id}",
        category: "simulation_proposed",
        title: Map.get(metadata, "title", "Proposed simulation"),
        summary: Map.get(metadata, "rationale", "Review and approve to run."),
        node_type: "simulation",
        node_id: sim.id,
        urgency: "action",
        timestamp: sim.inserted_at,
        connections: %{},
        metadata: %{
          proposed_by: Map.get(metadata, "proposed_by"),
          source_agent: Map.get(metadata, "proposed_by")
        }
      }
    end)
  end

  defp pending_knowledge_stream_items(project_id) do
    KnowledgeEntry
    |> where(
      [k],
      k.project_id == ^project_id and k.status == "pending_review" and
        k.source_type == "generated"
    )
    |> order_by([k], desc: k.inserted_at)
    |> limit(3)
    |> Repo.all()
    |> Enum.map(fn entry ->
      proposer =
        case entry.assigned_personas do
          [persona | _] -> persona
          _ -> "agent"
        end

      %{
        id: "knowledge-pending-#{entry.id}",
        category: "knowledge_proposed",
        title: entry.title,
        summary: String.slice(entry.content || "", 0, 200),
        node_type: "knowledge_entry",
        node_id: entry.id,
        urgency: "action",
        timestamp: entry.inserted_at,
        connections: %{},
        metadata: %{
          entry_type: entry.entry_type,
          source_agent: proposer,
          rationale: Map.get(entry.metadata || %{}, "rationale")
        }
      }
    end)
  end

  # -------------------------------------------------------------------
  # Recently — informational
  # -------------------------------------------------------------------

  defp generate_recently(project_id, since) do
    cutoff = since || DateTime.utc_now() |> DateTime.add(-86400)

    resolved_flags =
      GraphFlag
      |> where(
        [f],
        f.project_id == ^project_id and f.status == "resolved" and f.updated_at > ^cutoff
      )
      |> order_by([f], desc: f.updated_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn flag ->
        node_title = resolve_node_title(flag.node_type, flag.node_id)

        %{
          id: "flag-resolved-#{flag.id}",
          category: "status_change",
          title: "Resolved: #{node_title || flag.node_type}",
          summary: "#{flag.flag_type} resolved by #{flag.resolved_by || "system"}",
          node_type: flag.node_type,
          node_id: flag.node_id,
          urgency: "info",
          timestamp: flag.updated_at,
          connections: %{},
          metadata: %{flag_id: flag.id}
        }
      end)

    recent_insights =
      Insight
      |> where(
        [i],
        i.project_id == ^project_id and i.status != "draft" and i.updated_at > ^cutoff
      )
      |> order_by([i], desc: i.updated_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn insight ->
        connections = connection_counts(project_id, "insight", insight.id)

        %{
          id: "insight-#{insight.id}",
          category: "insight_created",
          title: insight.title,
          summary: String.slice(insight.body || "", 0, 200),
          node_type: "insight",
          node_id: insight.id,
          urgency: "info",
          timestamp: insight.updated_at,
          connections: connections,
          metadata: %{status: insight.status}
        }
      end)

    recent_decisions =
      Decision
      |> where(
        [d],
        d.project_id == ^project_id and d.status != "draft" and d.updated_at > ^cutoff
      )
      |> order_by([d], desc: d.updated_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn decision ->
        connections = connection_counts(project_id, "decision", decision.id)

        %{
          id: "decision-#{decision.id}",
          category: "decision_created",
          title: decision.title,
          summary: String.slice(decision.body || "", 0, 200),
          node_type: "decision",
          node_id: decision.id,
          urgency: "info",
          timestamp: decision.updated_at,
          connections: connections,
          metadata: %{status: decision.status}
        }
      end)

    recent_artifacts =
      Artifact
      |> where([a], a.project_id == ^project_id and a.version > 1 and a.updated_at > ^cutoff)
      |> order_by([a], desc: a.updated_at)
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn artifact ->
        %{
          id: "artifact-#{artifact.id}",
          category: "artifact_updated",
          title: artifact.title,
          summary: "Version #{artifact.version} by #{artifact.last_updated_by || "system"}",
          node_type: "artifact",
          node_id: artifact.id,
          urgency: "info",
          timestamp: artifact.updated_at,
          connections: %{},
          metadata: %{
            artifact_type: artifact.artifact_type,
            change_summary: (artifact.metadata || %{})["last_change_summary"],
            source_agent: artifact.last_updated_by
          }
        }
      end)

    completed_simulations =
      SimulationNode
      |> where(
        [s],
        s.project_id == ^project_id and s.status == "completed" and s.updated_at > ^cutoff
      )
      |> order_by([s], desc: s.updated_at)
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn sim ->
        metadata = sim.metadata || %{}

        %{
          id: "simulation-completed-#{sim.id}",
          category: "simulation_completed",
          title: Map.get(metadata, "title", "Simulation ##{sim.id}"),
          summary: "Simulation completed. Review results and recommendations.",
          node_type: "simulation",
          node_id: sim.id,
          urgency: "info",
          timestamp: sim.updated_at,
          connections: %{},
          metadata: %{
            title: Map.get(metadata, "title"),
            proposed_by: Map.get(metadata, "proposed_by"),
            source_agent: Map.get(metadata, "proposed_by")
          }
        }
      end)

    accepted_knowledge =
      KnowledgeEntry
      |> where(
        [k],
        k.project_id == ^project_id and k.source_type == "generated" and k.status == "active" and
          k.updated_at > ^cutoff
      )
      |> order_by([k], desc: k.updated_at)
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn entry ->
        %{
          id: "knowledge-activated-#{entry.id}",
          category: "knowledge_activated",
          title: "Knowledge activated: #{entry.title}",
          summary: String.slice(entry.content || "", 0, 200),
          node_type: "knowledge_entry",
          node_id: entry.id,
          urgency: "info",
          timestamp: entry.updated_at,
          connections: %{},
          metadata: %{entry_type: entry.entry_type}
        }
      end)

    (resolved_flags ++
       recent_insights ++
       recent_decisions ++ recent_artifacts ++ completed_simulations ++ accepted_knowledge)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(15)
  end

  # -------------------------------------------------------------------
  # Emerging — proactive findings
  # -------------------------------------------------------------------

  defp generate_emerging(project_id) do
    GraphFlag
    |> where(
      [f],
      f.project_id == ^project_id and f.status == "open" and
        f.flag_type in ["stale", "orphaned", "confidence_decayed"]
    )
    |> order_by([f], desc: f.inserted_at)
    |> limit(5)
    |> Repo.all()
    |> Enum.map(fn flag ->
      node_title = resolve_node_title(flag.node_type, flag.node_id)
      connections = connection_counts(project_id, flag.node_type, flag.node_id)

      %{
        id: "emerging-#{flag.id}",
        category: "agent_finding",
        title: node_title || "#{flag.node_type}##{flag.node_id}",
        summary: flag.reason || "Attention suggested",
        node_type: flag.node_type,
        node_id: flag.node_id,
        urgency: "emerging",
        timestamp: flag.inserted_at,
        connections: connections,
        metadata: %{flag_id: flag.id, flag_type: flag.flag_type, source_agent: flag.source_agent}
      }
    end)
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp resolve_node_title(node_type, node_id) do
    case Graph.resolve_node(node_type, node_id) do
      {:ok, %{title: title}} when is_binary(title) and title != "" -> title
      _ -> nil
    end
  end

  defp connection_counts(project_id, node_type, node_id) do
    outgoing =
      GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and e.from_node_type == ^node_type and
          e.from_node_id == ^node_id
      )
      |> select([e], {e.to_node_type, count(e.id)})
      |> group_by([e], e.to_node_type)
      |> Repo.all()

    incoming =
      GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and e.to_node_type == ^node_type and e.to_node_id == ^node_id
      )
      |> select([e], {e.from_node_type, count(e.id)})
      |> group_by([e], e.from_node_type)
      |> Repo.all()

    (outgoing ++ incoming)
    |> Enum.reduce(%{}, fn {type, count}, acc ->
      Map.update(acc, type, count, &(&1 + count))
    end)
  end

  # -------------------------------------------------------------------
  # Narrative generation
  # -------------------------------------------------------------------

  defp put_narrative(project_id, item) do
    narrative = generate_narrative(project_id, item)
    Map.put(item, :narrative, narrative)
  end

  # Autonomous work attribution — check first since it applies across categories
  defp generate_narrative(
         _project_id,
         %{metadata: %{autonomous: true, initiative_source: true}} = item
       ) do
    agent =
      case Map.get(item.metadata, :source_agent) do
        nil -> "An agent"
        a -> String.capitalize(to_string(a))
      end

    "#{agent} identified this proactively based on the current graph state."
  end

  # Artifact updates
  defp generate_narrative(_project_id, %{category: "artifact_updated"} = item) do
    case Map.get(item.metadata, :change_summary) do
      summary when is_binary(summary) and summary != "" -> summary
      _ -> "Updated based on recent graph changes."
    end
  end

  # Flags — contradictions
  defp generate_narrative(_project_id, %{category: "flag", metadata: %{flag_type: "contradicted"}}) do
    "Conflicting evidence detected. This may affect downstream requirements and tasks."
  end

  # Flags — needs_review (already action items, give helpful context)
  defp generate_narrative(project_id, %{category: "flag", node_type: node_type, node_id: node_id})
       when is_binary(node_type) and is_integer(node_id) do
    downstream = Graph.edges_from(project_id, node_type, node_id)

    if length(downstream) > 0 do
      count = length(downstream)

      "This node has #{count} downstream dependenc#{if count == 1, do: "y", else: "ies"} that may be affected."
    else
      nil
    end
  end

  # New insights — check what they connect to
  defp generate_narrative(project_id, %{
         category: "insight_created",
         node_type: "insight",
         node_id: id
       }) do
    # Check for contradictions on this specific insight
    flags = Graph.open_flags(project_id, node_type: "insight", flag_type: "contradicted")
    contradicted = Enum.any?(flags, &(&1.node_id == id))

    if contradicted do
      "This insight contradicts existing evidence. Review the conflicting data before it affects downstream decisions."
    else
      downstream = Graph.edges_from(project_id, "insight", id)

      if length(downstream) > 0 do
        affected_titles =
          downstream
          |> Enum.take(2)
          |> Enum.map(fn e -> resolve_node_title(e.to_node_type, e.to_node_id) end)
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" and ")

        if affected_titles != "" do
          "This strengthens the evidence for #{affected_titles}."
        else
          "New research finding. Consider whether this warrants a product decision."
        end
      else
        "New research finding. Consider whether this warrants a product decision."
      end
    end
  end

  # Decision gates — check supporting evidence
  defp generate_narrative(project_id, %{
         category: "decision_gate",
         node_type: node_type,
         node_id: node_id
       }) do
    upstream = Graph.edges_to(project_id, node_type, node_id)
    insight_count = Enum.count(upstream, &(&1.from_node_type == "insight"))

    if insight_count > 0 do
      "Backed by #{insight_count} research insight#{if insight_count != 1, do: "s", else: ""}. Ready for your review."
    else
      "No linked research evidence yet. Consider gathering data before deciding."
    end
  end

  # Emerging — stale nodes
  defp generate_narrative(_project_id, %{
         category: "agent_finding",
         metadata: %{flag_type: "stale"}
       }) do
    "This hasn't been reviewed in over 90 days. The evidence may no longer reflect current conditions."
  end

  # Emerging — orphaned nodes
  defp generate_narrative(_project_id, %{
         category: "agent_finding",
         metadata: %{flag_type: "orphaned"}
       }) do
    "This node has no incoming lineage edges. Consider linking it to its source or archiving it."
  end

  # Emerging — confidence decay
  defp generate_narrative(_project_id, %{
         category: "agent_finding",
         metadata: %{flag_type: "confidence_decayed"}
       }) do
    "Confidence has decayed over time. Re-validate against current data."
  end

  # Knowledge proposed
  defp generate_narrative(_project_id, %{category: "knowledge_proposed"} = item) do
    rationale = Map.get(item.metadata, :rationale)
    if rationale, do: to_string(rationale), else: "Review and activate to add to agent context."
  end

  # Simulation completed
  defp generate_narrative(_project_id, %{category: "simulation_completed"} = item) do
    title = Map.get(item.metadata, :title, "Simulation")
    "#{title} finished. Review results and recommendations."
  end

  # Default — no narrative
  defp generate_narrative(_project_id, _item), do: nil

  # -------------------------------------------------------------------
  # Item grouping
  # -------------------------------------------------------------------

  defp group_related_items(items) do
    # Group by (source_agent, node_type) then split groups that span > @group_window_seconds
    items
    |> Enum.group_by(fn item ->
      {Map.get(item[:metadata] || %{}, :source_agent), item[:node_type]}
    end)
    |> Enum.flat_map(fn {_key, group_items} ->
      split_by_time_window(Enum.sort_by(group_items, & &1.timestamp, {:desc, DateTime}))
    end)
    |> Enum.sort_by(
      fn
        %{type: :group, timestamp: ts} -> ts
        %{timestamp: ts} -> ts
      end,
      {:desc, DateTime}
    )
  end

  defp split_by_time_window(sorted_items) do
    sorted_items
    |> Enum.chunk_while(
      [],
      fn item, acc ->
        case acc do
          [] ->
            {:cont, [item]}

          [first | _] ->
            diff = abs(DateTime.diff(first.timestamp, item.timestamp, :second))

            if diff <= @group_window_seconds do
              {:cont, [item | acc]}
            else
              {:cont, wrap_group(Enum.reverse(acc)), [item]}
            end
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, wrap_group(Enum.reverse(acc)), []}
      end
    )
    |> List.flatten()
  end

  defp wrap_group([single]), do: [single]

  defp wrap_group(items) when length(items) > 1 do
    first = hd(items)
    agent = Map.get(first[:metadata] || %{}, :source_agent, "agent")
    node_type = first[:node_type] || "item"
    count = length(items)

    [
      %{
        id: "group-#{first.id}",
        type: :group,
        items: items,
        title: "#{count} new #{node_type}s from #{agent}",
        narrative:
          "The #{agent} produced #{count} #{node_type}s. Review them to update the product graph.",
        timestamp: first.timestamp
      }
    ]
  end

  defp wrap_group([]), do: []
end
