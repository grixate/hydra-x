defmodule HydraX.Product.MyWork do
  @moduledoc """
  Aggregates personal work data from multiple sources for the "My Work" view.
  """

  import Ecto.Query

  alias HydraX.Product.BoardNode
  alias HydraX.Product.BoardSession
  alias HydraX.Product.GraphFlag
  alias HydraX.Product.Insight
  alias HydraX.Product.Decision
  alias HydraX.Product.Requirement
  alias HydraX.Product.Routine
  alias HydraX.Product.Task, as: ProductTask
  alias HydraX.Repo

  @recent_days 7

  @doc """
  Generate the full My Work data for a project.
  Returns needs_input, active_work, and recent_output sections.
  """
  def generate(project_id, opts \\ []) do
    user_identifier = Keyword.get(opts, :user_identifier)

    %{
      needs_input: needs_input_items(project_id, user_identifier),
      active_work: active_work_items(project_id, user_identifier),
      recent_output: recent_output_items(project_id, user_identifier)
    }
  end

  @doc """
  Return badge counts for the sidebar.
  """
  def counts(project_id) do
    needs_input = length(needs_input_items(project_id, nil))

    active_work =
      ProductTask
      |> where([t], t.project_id == ^project_id and t.status in ["in_progress", "review"])
      |> Repo.aggregate(:count, :id)

    %{needs_input: needs_input, active_work: active_work}
  end

  @doc """
  Return work data for a specific agent.
  """
  def agent_work(project_id, agent_slug) do
    persona = agent_slug_to_persona(agent_slug)

    %{
      current: current_agent_work(project_id, persona),
      completed: completed_agent_work(project_id, persona),
      queued: queued_agent_work(project_id, persona)
    }
  end

  # --- Needs Input ---

  defp needs_input_items(project_id, _user_identifier) do
    draft_nodes = draft_graph_nodes(project_id)
    open_flags = open_graph_flags(project_id)
    promotion_ready = promotion_ready_sessions(project_id)

    draft_nodes ++ open_flags ++ promotion_ready
  end

  defp draft_graph_nodes(project_id) do
    draft_insights =
      Insight
      |> where([i], i.project_id == ^project_id and i.status == "draft")
      |> order_by([i], desc: i.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn i ->
        %{
          type: "agent_review",
          title: "Review draft insight: #{i.title}",
          node_type: "insight",
          node_id: i.id,
          agent: "researcher",
          created_at: i.inserted_at,
          actions: ["approve", "reject", "revise"]
        }
      end)

    draft_decisions =
      Decision
      |> where([d], d.project_id == ^project_id and d.status == "draft")
      |> order_by([d], desc: d.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn d ->
        %{
          type: "agent_review",
          title: "Review draft decision: #{d.title}",
          node_type: "decision",
          node_id: d.id,
          agent: "strategist",
          created_at: d.inserted_at,
          actions: ["approve", "reject", "revise"]
        }
      end)

    draft_requirements =
      Requirement
      |> where([r], r.project_id == ^project_id and r.status == "draft")
      |> order_by([r], desc: r.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn r ->
        %{
          type: "agent_review",
          title: "Review draft requirement: #{r.title}",
          node_type: "requirement",
          node_id: r.id,
          agent: "strategist",
          created_at: r.inserted_at,
          actions: ["approve", "reject", "revise"]
        }
      end)

    (draft_insights ++ draft_decisions ++ draft_requirements)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    |> Enum.take(10)
  end

  defp open_graph_flags(project_id) do
    GraphFlag
    |> where([f], f.project_id == ^project_id and f.status == "open")
    |> where([f], f.flag_type in ["needs_review", "contradicted"])
    |> order_by([f], desc: f.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn f ->
      %{
        type: "flag",
        title: "Flag: #{f.description || f.flag_type} on #{f.node_type} ##{f.node_id}",
        node_type: f.node_type,
        node_id: f.node_id,
        flag_type: f.flag_type,
        created_at: f.inserted_at,
        actions: ["review"]
      }
    end)
  end

  defp promotion_ready_sessions(project_id) do
    # Use a subquery to count draft nodes per session to avoid loading all nodes into memory
    draft_counts =
      BoardNode
      |> where([n], n.project_id == ^project_id and n.status == "draft")
      |> group_by([n], n.board_session_id)
      |> select([n], {n.board_session_id, count(n.id)})
      |> Repo.all()
      |> Map.new()

    if map_size(draft_counts) == 0 do
      []
    else
      session_ids = Map.keys(draft_counts)

      BoardSession
      |> where([s], s.id in ^session_ids and s.status == "active")
      |> Repo.all()
      |> Enum.map(fn session ->
        count = Map.get(draft_counts, session.id, 0)

        %{
          type: "promotion_ready",
          title: "#{count} nodes ready in '#{session.title}'",
          session_id: session.id,
          session_title: session.title,
          node_count: count,
          created_at: session.updated_at,
          actions: ["review_session"]
        }
      end)
    end
  end

  # --- Active Work ---

  defp active_work_items(project_id, _user_identifier) do
    active_tasks = active_tasks(project_id)
    active_sessions = active_board_sessions(project_id)

    active_tasks ++ active_sessions
  end

  defp active_tasks(project_id) do
    ProductTask
    |> where([t], t.project_id == ^project_id and t.status in ["in_progress", "review"])
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        type: "task",
        title: t.title,
        node_type: "task",
        node_id: t.id,
        priority: t.priority,
        status: t.status,
        assignee: t.assignee,
        updated_at: t.updated_at
      }
    end)
  end

  defp active_board_sessions(project_id) do
    # Count draft nodes per session via subquery instead of preloading all nodes
    draft_counts =
      BoardNode
      |> where([n], n.project_id == ^project_id and n.status == "draft")
      |> group_by([n], n.board_session_id)
      |> select([n], {n.board_session_id, count(n.id)})
      |> Repo.all()
      |> Map.new()

    BoardSession
    |> where([s], s.project_id == ^project_id and s.status == "active")
    |> order_by([s], desc: s.updated_at)
    |> Repo.all()
    |> Enum.map(fn session ->
      %{
        type: "board_session",
        session_id: session.id,
        title: session.title,
        draft_node_count: Map.get(draft_counts, session.id, 0),
        last_active_at: session.updated_at
      }
    end)
  end

  # --- Recent Output ---

  defp recent_output_items(project_id, _user_identifier) do
    since = DateTime.add(DateTime.utc_now(), -@recent_days * 86400, :second)

    completed_tasks = recently_completed_tasks(project_id, since)
    promoted_nodes = recently_promoted_nodes(project_id, since)

    (completed_tasks ++ promoted_nodes)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(20)
  end

  defp recently_completed_tasks(project_id, since) do
    ProductTask
    |> where([t], t.project_id == ^project_id and t.status == "done")
    |> where([t], t.updated_at >= ^since)
    |> order_by([t], desc: t.updated_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn t ->
      %{type: "completed_task", title: "Completed: #{t.title}", node_id: t.id, at: t.updated_at}
    end)
  end

  defp recently_promoted_nodes(project_id, since) do
    BoardNode
    |> where([n], n.project_id == ^project_id and n.status == "promoted")
    |> where([n], n.updated_at >= ^since)
    |> preload([:board_session])
    |> order_by([n], desc: n.updated_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(fn n ->
      session_title =
        if Ecto.assoc_loaded?(n.board_session) and n.board_session,
          do: n.board_session.title,
          else: "unknown session"

      %{
        type: "promoted",
        title: "Promoted #{n.node_type}: #{n.title} from '#{session_title}'",
        node_id: n.promoted_node_id,
        node_type: n.promoted_node_type,
        session_id: n.board_session_id,
        at: n.updated_at
      }
    end)
  end

  # --- Agent Work ---

  defp current_agent_work(project_id, persona) do
    Routine
    |> where([r], r.project_id == ^project_id and r.persona == ^persona and r.active == true)
    |> Repo.all()
    |> Enum.map(fn r ->
      %{type: "routine", title: "Running routine: #{r.title}", routine_id: r.id}
    end)
  end

  defp completed_agent_work(project_id, persona) do
    since = DateTime.add(DateTime.utc_now(), -@recent_days * 86400, :second)

    board_nodes =
      BoardNode
      |> where([n], n.project_id == ^project_id and n.created_by == ^"agent:#{persona}")
      |> where([n], n.inserted_at >= ^since)
      |> order_by([n], desc: n.inserted_at)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn n ->
        %{
          type: "board_node_created",
          title: "Created #{n.node_type}: #{n.title}",
          node_id: n.id,
          status: n.status,
          at: n.inserted_at
        }
      end)

    board_nodes
  end

  defp queued_agent_work(project_id, persona) do
    Routine
    |> where([r], r.project_id == ^project_id and r.persona == ^persona and r.active == true)
    |> where([r], not is_nil(r.schedule))
    |> Repo.all()
    |> Enum.map(fn r ->
      %{
        type: "scheduled_routine",
        title: "Scheduled: #{r.title}",
        routine_id: r.id,
        schedule: r.schedule
      }
    end)
  end

  defp agent_slug_to_persona(slug) do
    case slug do
      "researcher" -> "researcher"
      "strategist" -> "strategist"
      "architect" -> "architect"
      "designer" -> "designer"
      "memory" -> "memory_agent"
      "memory_agent" -> "memory_agent"
      other -> other
    end
  end
end
