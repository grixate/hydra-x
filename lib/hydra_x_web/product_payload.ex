defmodule HydraXWeb.ProductPayload do
  @moduledoc false

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Product.Project

  def project_json(%Project{} = project) do
    %{
      id: project.id,
      name: project.name,
      slug: project.slug,
      description: project.description,
      status: project.status,
      metadata: project.metadata || %{},
      researcher_agent: agent_json(project.researcher_agent),
      strategist_agent: agent_json(project.strategist_agent),
      architect_agent: agent_json(project.architect_agent),
      designer_agent: agent_json(project.designer_agent),
      memory_agent: agent_json(project.memory_agent),
      inserted_at: project.inserted_at,
      updated_at: project.updated_at
    }
  end

  def source_json(%GraphNode{type_key: "source"} = source, include_chunks? \\ false) do
    attrs = source.attributes || %{}

    chunks =
      if include_chunks? do
        source
        |> loaded_assoc(:source_chunks)
        |> Enum.sort_by(& &1.ordinal)
        |> Enum.map(fn chunk ->
          %{
            id: chunk.id,
            ordinal: chunk.ordinal,
            content: chunk.content,
            token_count: chunk.token_count,
            metadata: chunk.metadata || %{},
            inserted_at: chunk.inserted_at,
            updated_at: chunk.updated_at
          }
        end)
      else
        nil
      end

    %{
      id: source.id,
      project_id: source.project_id,
      title: source.title,
      source_type: Map.get(attrs, "source_type"),
      external_ref: Map.get(attrs, "external_ref"),
      processing_status: source.status,
      content: source.body,
      metadata: attrs,
      source_chunk_count: length(loaded_assoc(source, :source_chunks)),
      chunks: chunks,
      # Source-as-Data (Cycle 3)
      promoted_to_graph: Map.get(attrs, "promoted_to_graph", false),
      promoted_at: Map.get(attrs, "promoted_at"),
      archived_at: source.archived_at,
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    }
  end

  def insight_json(%GraphNode{type_key: "insight"} = insight) do
    %{
      id: insight.id,
      project_id: insight.project_id,
      title: insight.title,
      body: insight.body,
      status: insight.status,
      metadata: insight.attributes || %{},
      evidence:
        Enum.map(loaded_assoc(insight, :insight_evidence), fn evidence ->
          %{
            id: evidence.id,
            source_chunk_id: evidence.source_chunk_id,
            quote: evidence.quote,
            metadata: evidence.metadata || %{},
            source_chunk:
              if(evidence.source_chunk,
                do: %{
                  id: evidence.source_chunk.id,
                  source_id: evidence.source_chunk.source_id,
                  source_title:
                    evidence.source_chunk.source && evidence.source_chunk.source.title,
                  content: evidence.source_chunk.content,
                  ordinal: evidence.source_chunk.ordinal
                }
              )
          }
        end),
      linked_requirements:
        Enum.map(loaded_assoc(insight, :requirement_insights), fn link ->
          %{
            requirement_id: link.requirement_id,
            metadata: link.metadata || %{}
          }
        end),
      inserted_at: insight.inserted_at,
      updated_at: insight.updated_at
    }
  end

  def requirement_json(%GraphNode{type_key: "requirement"} = requirement) do
    attrs = requirement.attributes || %{}

    %{
      id: requirement.id,
      project_id: requirement.project_id,
      title: requirement.title,
      body: requirement.body,
      status: requirement.status,
      grounded: Map.get(attrs, "grounded", false),
      metadata: attrs,
      insights:
        Enum.map(loaded_assoc(requirement, :linked_requirement_insights), fn link ->
          insight = link.insight

          %{
            id: insight.id,
            title: insight.title,
            body: insight.body,
            status: insight.status,
            evidence:
              Enum.map(loaded_assoc(insight, :insight_evidence), fn evidence ->
                %{
                  source_chunk_id: evidence.source_chunk_id,
                  quote: evidence.quote,
                  source_chunk:
                    if(evidence.source_chunk,
                      do: %{
                        id: evidence.source_chunk.id,
                        source_id: evidence.source_chunk.source_id,
                        source_title:
                          evidence.source_chunk.source && evidence.source_chunk.source.title,
                        content: evidence.source_chunk.content,
                        ordinal: evidence.source_chunk.ordinal
                      }
                    )
                }
              end)
          }
        end),
      inserted_at: requirement.inserted_at,
      updated_at: requirement.updated_at
    }
  end

  def watch_target_json(%HydraX.Product.WatchTarget{} = target) do
    %{
      id: target.id,
      project_id: target.project_id,
      target_type: target.target_type,
      value: target.value,
      check_interval_hours: target.check_interval_hours,
      last_checked_at: target.last_checked_at,
      status: target.status,
      metadata: target.metadata || %{},
      inserted_at: target.inserted_at,
      updated_at: target.updated_at
    }
  end

  def decision_json(%GraphNode{type_key: "decision"} = d) do
    attrs = d.attributes || %{}

    %{
      id: d.id,
      project_id: d.project_id,
      title: d.title,
      body: d.body,
      status: d.status,
      decided_by: Map.get(attrs, "decided_by"),
      decided_at: Map.get(attrs, "decided_at"),
      alternatives_considered: Map.get(attrs, "alternatives_considered", []),
      metadata: attrs,
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    }
  end

  def strategy_json(%GraphNode{type_key: "strategy"} = s) do
    %{
      id: s.id,
      project_id: s.project_id,
      title: s.title,
      body: s.body,
      status: s.status,
      metadata: s.attributes || %{},
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end

  def design_node_json(%GraphNode{type_key: "design_node"} = d) do
    attrs = d.attributes || %{}

    %{
      id: d.id,
      project_id: d.project_id,
      title: d.title,
      body: d.body,
      node_type: Map.get(attrs, "node_type"),
      status: d.status,
      metadata: attrs,
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    }
  end

  def architecture_node_json(%GraphNode{type_key: "architecture_node"} = a) do
    attrs = a.attributes || %{}

    %{
      id: a.id,
      project_id: a.project_id,
      title: a.title,
      body: a.body,
      node_type: Map.get(attrs, "node_type"),
      status: a.status,
      metadata: attrs,
      inserted_at: a.inserted_at,
      updated_at: a.updated_at
    }
  end

  def agent_task_json(%HydraX.Product.AgentTask{} = t) do
    %{
      id: t.id,
      project_id: t.project_id,
      agent_id: t.agent_id,
      title: t.title,
      description: t.description,
      state: t.state,
      state_reason: t.state_reason,
      priority: t.priority,
      progress_current: t.progress_current,
      progress_total: t.progress_total,
      progress_label: t.progress_label,
      context_type: t.context_type,
      context_id: t.context_id,
      parent_task_id: t.parent_task_id,
      assigned_by: t.assigned_by,
      assigned_by_user_id: t.assigned_by_user_id,
      assigned_by_agent_id: t.assigned_by_agent_id,
      proposal_payload: t.proposal_payload,
      result_payload: t.result_payload,
      error_payload: t.error_payload,
      started_at: t.started_at,
      completed_at: t.completed_at,
      last_state_change_at: t.last_state_change_at,
      lock_version: t.lock_version,
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  def task_json(%GraphNode{type_key: "task"} = t) do
    attrs = t.attributes || %{}

    %{
      id: t.id,
      project_id: t.project_id,
      title: t.title,
      body: t.body,
      status: t.status,
      priority: Map.get(attrs, "priority"),
      assignee: Map.get(attrs, "assignee"),
      effort_estimate: Map.get(attrs, "effort_estimate"),
      metadata: attrs,
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  def learning_json(%GraphNode{type_key: "learning"} = l) do
    attrs = l.attributes || %{}

    %{
      id: l.id,
      project_id: l.project_id,
      title: l.title,
      body: l.body,
      learning_type: Map.get(attrs, "learning_type"),
      status: l.status,
      metadata: attrs,
      inserted_at: l.inserted_at,
      updated_at: l.updated_at
    }
  end

  def constraint_json(%GraphNode{type_key: "constraint"} = c) do
    attrs = c.attributes || %{}

    %{
      id: c.id,
      project_id: c.project_id,
      title: c.title,
      body: c.body,
      scope: Map.get(attrs, "reach_scope", "global"),
      enforcement: Map.get(attrs, "enforcement", "strict"),
      status: c.status,
      metadata: attrs,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  def routine_json(%GraphNode{type_key: "routine"} = r) do
    attrs = r.attributes || %{}

    %{
      id: r.id,
      project_id: r.project_id,
      title: r.title,
      description: r.body,
      prompt_template: Map.get(attrs, "prompt_template"),
      assigned_persona: Map.get(attrs, "assigned_persona"),
      schedule_type: Map.get(attrs, "schedule_type"),
      cron_expression: Map.get(attrs, "cron_expression"),
      event_trigger: Map.get(attrs, "event_trigger"),
      timezone: Map.get(attrs, "timezone"),
      output_target: Map.get(attrs, "output_target"),
      status: r.status,
      last_run_at: Map.get(attrs, "last_run_at"),
      last_run_status: Map.get(attrs, "last_run_status"),
      last_run_tokens: Map.get(attrs, "last_run_tokens"),
      metadata: attrs,
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
  end

  def routine_run_json(%HydraX.Product.RoutineRun{} = r) do
    %{
      id: r.id,
      routine_id: r.routine_id,
      started_at: r.started_at,
      completed_at: r.completed_at,
      status: r.status,
      prompt_resolved: r.prompt_resolved,
      output: r.output,
      token_count: r.token_count,
      cost_cents: r.cost_cents,
      metadata: r.metadata || %{},
      inserted_at: r.inserted_at
    }
  end

  def knowledge_entry_json(%GraphNode{type_key: "knowledge_entry"} = k) do
    attrs = k.attributes || %{}

    %{
      id: k.id,
      project_id: k.project_id,
      title: k.title,
      content: k.body,
      entry_type: Map.get(attrs, "entry_type"),
      assigned_personas: Map.get(attrs, "assigned_personas", []),
      source_type: Map.get(attrs, "source_type"),
      source_url: Map.get(attrs, "source_url"),
      status: k.status,
      metadata: attrs,
      inserted_at: k.inserted_at,
      updated_at: k.updated_at
    }
  end

  def task_feedback_json(%HydraX.Product.TaskFeedback{} = f) do
    %{
      id: f.id,
      task_id: f.task_id,
      rating: f.rating,
      comment: f.comment,
      feedback_tags: f.feedback_tags,
      created_by: f.created_by,
      metadata: f.metadata || %{},
      inserted_at: f.inserted_at
    }
  end

  def graph_flag_json(%HydraX.Product.GraphFlag{} = f) do
    %{
      id: f.id,
      project_id: f.project_id,
      node_type: f.node_type,
      node_id: f.node_id,
      flag_type: f.flag_type,
      reason: f.reason,
      source_agent: f.source_agent,
      status: f.status,
      resolved_by: f.resolved_by,
      resolved_at: f.resolved_at,
      inserted_at: f.inserted_at,
      updated_at: f.updated_at
    }
  end

  def graph_node_json(node) do
    base = %{
      id: node.id,
      project_id: node.project_id,
      title: node.title,
      body: node.body,
      status: node.status,
      metadata: node.metadata || %{},
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }

    cond do
      Map.has_key?(node, :node_type) ->
        Map.put(base, :node_type, node.node_type)

      Map.has_key?(node, :priority) ->
        Map.merge(base, %{
          priority: node.priority,
          assignee: node.assignee,
          effort_estimate: node.effort_estimate
        })

      Map.has_key?(node, :decided_by) ->
        Map.merge(base, %{
          decided_by: node.decided_by,
          decided_at: node.decided_at,
          alternatives_considered: node.alternatives_considered
        })

      Map.has_key?(node, :learning_type) ->
        Map.put(base, :learning_type, node.learning_type)

      true ->
        base
    end
  end

  def stream_item_json(item) do
    %{
      id: item.id,
      category: item.category,
      title: item.title,
      summary: item.summary,
      node_type: item.node_type,
      node_id: item.node_id,
      urgency: item.urgency,
      timestamp: item.timestamp,
      metadata: item.metadata || %{}
    }
  end

  defp agent_json(nil), do: nil

  defp agent_json(agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      role: agent.role,
      workspace_root: agent.workspace_root,
      status: agent.status
    }
  end

  def board_session_json(%HydraX.Product.BoardSession{} = s) do
    nodes = loaded_assoc(s, :board_nodes)
    draft_count = Enum.count(nodes, &(&1.status == "draft"))
    promoted_count = Enum.count(nodes, &(&1.status == "promoted"))

    node_types =
      nodes
      |> Enum.map(& &1.node_type)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    active_agents =
      nodes
      |> Enum.map(& &1.created_by)
      |> Enum.reject(fn c -> c in [nil, "human"] end)
      |> Enum.uniq()

    %{
      id: s.id,
      project_id: s.project_id,
      title: s.title,
      description: s.description,
      status: s.status,
      created_by_user_id: s.created_by_user_id,
      metadata: s.metadata || %{},
      draft_node_count: draft_count,
      promoted_node_count: promoted_count,
      total_node_count: length(nodes),
      node_types: node_types,
      active_agents: active_agents,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end

  def board_node_json(%HydraX.Product.BoardNode{} = n) do
    %{
      id: n.id,
      board_session_id: n.board_session_id,
      project_id: n.project_id,
      node_type: n.node_type,
      title: n.title,
      body: n.body,
      status: n.status,
      promoted_node_type: n.promoted_node_type,
      promoted_node_id: n.promoted_node_id,
      created_by: n.created_by,
      metadata: n.metadata || %{},
      inserted_at: n.inserted_at,
      updated_at: n.updated_at
    }
  end

  def board_edge_json(%HydraX.Product.BoardEdge{} = e) do
    %{
      id: e.id,
      board_session_id: e.board_session_id,
      from_board_node_id: e.from_board_node_id,
      to_board_node_id: e.to_board_node_id,
      kind: e.kind,
      metadata: e.metadata || %{},
      inserted_at: e.inserted_at,
      updated_at: e.updated_at
    }
  end

  def artifact_json(%GraphNode{type_key: "artifact"} = artifact) do
    attrs = artifact.attributes || %{}

    %{
      id: artifact.id,
      project_id: artifact.project_id,
      title: artifact.title,
      artifact_type: Map.get(attrs, "artifact_type"),
      body: artifact.body,
      owner_persona: Map.get(attrs, "owner_persona"),
      status: artifact.status,
      version: artifact.lock_version,
      last_updated_by: Map.get(attrs, "last_updated_by"),
      metadata: attrs,
      inserted_at: artifact.inserted_at,
      updated_at: artifact.updated_at
    }
  end

  def artifact_version_json(%HydraX.Product.ArtifactVersion{} = version) do
    %{
      id: version.id,
      artifact_id: version.artifact_id,
      version: version.version,
      body: version.body,
      change_summary: version.change_summary,
      updated_by: version.updated_by,
      metadata: version.metadata || %{},
      inserted_at: version.inserted_at
    }
  end

  defp loaded_assoc(struct, key) do
    case Map.get(struct, key) do
      %Ecto.Association.NotLoaded{} -> []
      values when is_list(values) -> values
      nil -> []
    end
  end
end
