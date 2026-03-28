defmodule HydraX.Product.Coherence do
  @moduledoc """
  Background agent that watches the product graph for inconsistencies,
  contradictions, and drift. Surfaces findings via graph flags and PubSub events.
  """

  alias HydraX.Product.Graph
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Repo

  import Ecto.Query

  # -------------------------------------------------------------------
  # Reactive checks (triggered by Propagation events)
  # -------------------------------------------------------------------

  def check_node_coherence(project_id, node_type, node_id) do
    outgoing = Graph.edges_from(project_id, node_type, node_id)
    incoming = Graph.edges_to(project_id, node_type, node_id)
    neighbor_refs = collect_neighbor_refs(outgoing, incoming)

    Enum.each(neighbor_refs, fn {neighbor_type, neighbor_id} ->
      check_stale_dependency(project_id, node_type, node_id, neighbor_type, neighbor_id)
    end)

    :ok
  end

  # -------------------------------------------------------------------
  # Autonomous deep scan (scheduled)
  # -------------------------------------------------------------------

  def full_scan(project_id) do
    orphans = Graph.orphaned_nodes(project_id)
    stale = Graph.stale_nodes(project_id, days: 90)
    flags = Graph.open_flags(project_id)

    orphan_count = length(orphans)
    stale_count = length(stale)
    flag_count = length(flags)

    # Flag orphans
    Enum.each(orphans, fn orphan ->
      Graph.flag_node(
        project_id,
        orphan.node_type,
        orphan.node_id,
        "orphaned",
        "Node has no incoming lineage edges",
        "coherence"
      )
    end)

    # Flag stale nodes
    Enum.each(stale, fn stale_node ->
      Graph.flag_node(
        project_id,
        stale_node.node_type,
        stale_node.node_id,
        "stale",
        "Node not updated since #{stale_node.updated_at}",
        "coherence"
      )
    end)

    # Check active requirements link to active insights
    broken_req_count = check_requirement_insight_chain(project_id)

    # Check active tasks link to active requirements
    broken_task_count = check_task_requirement_chain(project_id)

    total_issues = orphan_count + stale_count + broken_req_count + broken_task_count
    max_possible = max(orphan_count + stale_count + flag_count + broken_req_count + broken_task_count, 1)
    health_score = max(0.0, 1.0 - total_issues / max_possible)

    report = %{
      orphans: orphan_count,
      stale: stale_count,
      existing_flags: flag_count,
      broken_requirement_chains: broken_req_count,
      broken_task_chains: broken_task_count,
      health_score: Float.round(health_score, 2)
    }

    ProductPubSub.broadcast_project_event(
      project_id,
      "coherence.scan_completed",
      report
    )

    {:ok, report}
  end

  # -------------------------------------------------------------------
  # Contradiction detection
  # -------------------------------------------------------------------

  def detect_contradictions(_project_id, _node_a_type, _node_a_id, _node_b_type, _node_b_id) do
    # Placeholder for LLM-based contradiction detection.
    # Will be implemented when LLM integration is wired in.
    # Returns {:contradiction, reason} | :consistent | :uncertain
    :consistent
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp collect_neighbor_refs(outgoing, incoming) do
    out_refs = Enum.map(outgoing, fn e -> {e.to_node_type, e.to_node_id} end)
    in_refs = Enum.map(incoming, fn e -> {e.from_node_type, e.from_node_id} end)
    Enum.uniq(out_refs ++ in_refs)
  end

  defp check_stale_dependency(project_id, node_type, node_id, dep_type, dep_id) do
    case Graph.resolve_node(dep_type, dep_id) do
      {:ok, nil} ->
        Graph.flag_node(
          project_id,
          node_type,
          node_id,
          "needs_review",
          "Depends on #{dep_type}##{dep_id} which no longer exists",
          "coherence"
        )

      {:ok, dep} ->
        if Map.get(dep, :status) in ["archived", "superseded"] do
          Graph.flag_node(
            project_id,
            node_type,
            node_id,
            "needs_review",
            "Depends on #{dep_type}##{dep_id} which is #{dep.status}",
            "coherence"
          )
        end

      _ ->
        :ok
    end
  end

  defp check_requirement_insight_chain(project_id) do
    # Find active requirements whose lineage insights are archived/superseded
    edges =
      HydraX.Product.GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and
          e.to_node_type == "requirement" and
          e.from_node_type == "insight" and
          e.kind == "lineage"
      )
      |> Repo.all()

    Enum.count(edges, fn edge ->
      case Graph.resolve_node("insight", edge.from_node_id) do
        {:ok, %{status: status}} when status in ["archived", "superseded", "rejected"] ->
          Graph.flag_node(
            project_id,
            "requirement",
            edge.to_node_id,
            "needs_review",
            "Linked insight##{edge.from_node_id} is #{status}",
            "coherence"
          )

          true

        _ ->
          false
      end
    end)
  end

  defp check_task_requirement_chain(project_id) do
    edges =
      HydraX.Product.GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and
          e.to_node_type == "task" and
          e.from_node_type == "requirement" and
          e.kind == "lineage"
      )
      |> Repo.all()

    Enum.count(edges, fn edge ->
      case Graph.resolve_node("requirement", edge.from_node_id) do
        {:ok, %{status: status}} when status in ["archived", "superseded"] ->
          Graph.flag_node(
            project_id,
            "task",
            edge.to_node_id,
            "needs_review",
            "Linked requirement##{edge.from_node_id} is #{status}",
            "coherence"
          )

          true

        _ ->
          false
      end
    end)
  end
end
