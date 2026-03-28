defmodule HydraX.Product.Stream do
  @moduledoc """
  Generates the personalized activity stream for a project — the curated feed
  of what needs attention, what happened recently, and what's emerging.
  """

  import Ecto.Query

  alias HydraX.Product.Decision
  alias HydraX.Product.GraphFlag
  alias HydraX.Product.Insight
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

    (flag_items ++ draft_insight_items ++ draft_decision_items)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp flag_stream_items(project_id) do
    GraphFlag
    |> where([f], f.project_id == ^project_id and f.status == "open" and f.flag_type in ["needs_review", "contradicted"])
    |> order_by([f], desc: f.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn flag ->
      %{
        id: "flag-#{flag.id}",
        category: "flag",
        title: "#{flag.flag_type}: #{flag.node_type}##{flag.node_id}",
        summary: flag.reason || "Review needed",
        node_type: flag.node_type,
        node_id: flag.node_id,
        urgency: "action",
        timestamp: flag.inserted_at,
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
      %{
        id: "insight-draft-#{insight.id}",
        category: "insight_created",
        title: "Draft insight: #{insight.title}",
        summary: String.slice(insight.body || "", 0, 120),
        node_type: "insight",
        node_id: insight.id,
        urgency: "action",
        timestamp: insight.inserted_at,
        metadata: %{}
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
      %{
        id: "decision-draft-#{decision.id}",
        category: "decision_gate",
        title: "Pending decision: #{decision.title}",
        summary: String.slice(decision.body || "", 0, 120),
        node_type: "decision",
        node_id: decision.id,
        urgency: "action",
        timestamp: decision.inserted_at,
        metadata: %{}
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
        %{
          id: "flag-resolved-#{flag.id}",
          category: "status_change",
          title: "Resolved: #{flag.flag_type} on #{flag.node_type}##{flag.node_id}",
          summary: "Resolved by #{flag.resolved_by || "system"}",
          node_type: flag.node_type,
          node_id: flag.node_id,
          urgency: "info",
          timestamp: flag.updated_at,
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
        %{
          id: "insight-#{insight.id}",
          category: "insight_created",
          title: insight.title,
          summary: String.slice(insight.body || "", 0, 120),
          node_type: "insight",
          node_id: insight.id,
          urgency: "info",
          timestamp: insight.updated_at,
          metadata: %{status: insight.status}
        }
      end)

    (resolved_flags ++ recent_insights)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(10)
  end

  # -------------------------------------------------------------------
  # Emerging — proactive findings
  # -------------------------------------------------------------------

  defp generate_emerging(project_id) do
    stale_flags =
      GraphFlag
      |> where([f], f.project_id == ^project_id and f.status == "open" and f.flag_type in ["stale", "orphaned", "confidence_decayed"])
      |> order_by([f], desc: f.inserted_at)
      |> limit(5)
      |> Repo.all()
      |> Enum.map(fn flag ->
        %{
          id: "emerging-#{flag.id}",
          category: "agent_finding",
          title: "#{flag.flag_type}: #{flag.node_type}##{flag.node_id}",
          summary: flag.reason || "Attention suggested",
          node_type: flag.node_type,
          node_id: flag.node_id,
          urgency: "emerging",
          timestamp: flag.inserted_at,
          metadata: %{flag_id: flag.id, flag_type: flag.flag_type, source_agent: flag.source_agent}
        }
      end)

    stale_flags
  end
end
