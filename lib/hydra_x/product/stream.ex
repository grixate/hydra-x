defmodule HydraX.Product.Stream do
  @moduledoc """
  Generates the personalized activity stream for a project.
  """

  import Ecto.Query

  alias HydraX.Product.Decision
  alias HydraX.Product.Graph
  alias HydraX.Product.GraphEdge
  alias HydraX.Product.GraphFlag
  alias HydraX.Product.Insight
  alias HydraX.Product.Requirement
  alias HydraX.Repo

  @max_right_now 5

  def generate_stream(project_id, opts \\ []) do
    _role = Keyword.get(opts, :role, "founder")
    since = Keyword.get(opts, :since)

    right_now = generate_right_now(project_id)
    recently = generate_recently(project_id, since)
    emerging = generate_emerging(project_id)

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

    (flag_items ++ draft_insight_items ++ draft_decision_items ++ draft_requirement_items)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp flag_stream_items(project_id) do
    GraphFlag
    |> where([f], f.project_id == ^project_id and f.status == "open" and f.flag_type in ["needs_review", "contradicted"])
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

  # -------------------------------------------------------------------
  # Recently — informational
  # -------------------------------------------------------------------

  defp generate_recently(project_id, since) do
    cutoff = since || DateTime.utc_now() |> DateTime.add(-86400)

    resolved_flags =
      GraphFlag
      |> where([f], f.project_id == ^project_id and f.status == "resolved" and f.updated_at > ^cutoff)
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
      |> where([i], i.project_id == ^project_id and i.status != "draft" and i.updated_at > ^cutoff)
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
      |> where([d], d.project_id == ^project_id and d.status != "draft" and d.updated_at > ^cutoff)
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

    (resolved_flags ++ recent_insights ++ recent_decisions)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(15)
  end

  # -------------------------------------------------------------------
  # Emerging — proactive findings
  # -------------------------------------------------------------------

  defp generate_emerging(project_id) do
    GraphFlag
    |> where([f], f.project_id == ^project_id and f.status == "open" and f.flag_type in ["stale", "orphaned", "confidence_decayed"])
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
      |> where([e], e.project_id == ^project_id and e.from_node_type == ^node_type and e.from_node_id == ^node_id)
      |> select([e], {e.to_node_type, count(e.id)})
      |> group_by([e], e.to_node_type)
      |> Repo.all()

    incoming =
      GraphEdge
      |> where([e], e.project_id == ^project_id and e.to_node_type == ^node_type and e.to_node_id == ^node_id)
      |> select([e], {e.from_node_type, count(e.id)})
      |> group_by([e], e.from_node_type)
      |> Repo.all()

    (outgoing ++ incoming)
    |> Enum.reduce(%{}, fn {type, count}, acc ->
      Map.update(acc, type, count, &(&1 + count))
    end)
  end
end
