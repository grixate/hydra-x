defmodule HydraXWeb.ProductPayload do
  @moduledoc false

  alias HydraX.Product.Insight
  alias HydraX.Product.Project
  alias HydraX.Product.Requirement
  alias HydraX.Product.Source

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

  def source_json(%Source{} = source, include_chunks? \\ false) do
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
      source_type: source.source_type,
      external_ref: source.external_ref,
      processing_status: source.processing_status,
      content: source.content,
      metadata: source.metadata || %{},
      source_chunk_count: length(loaded_assoc(source, :source_chunks)),
      chunks: chunks,
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    }
  end

  def insight_json(%Insight{} = insight) do
    %{
      id: insight.id,
      project_id: insight.project_id,
      title: insight.title,
      body: insight.body,
      status: insight.status,
      metadata: insight.metadata || %{},
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

  def requirement_json(%Requirement{} = requirement) do
    %{
      id: requirement.id,
      project_id: requirement.project_id,
      title: requirement.title,
      body: requirement.body,
      status: requirement.status,
      grounded: requirement.grounded,
      metadata: requirement.metadata || %{},
      insights:
        Enum.map(loaded_assoc(requirement, :requirement_insights), fn link ->
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

  def decision_json(%HydraX.Product.Decision{} = d) do
    %{
      id: d.id,
      project_id: d.project_id,
      title: d.title,
      body: d.body,
      status: d.status,
      decided_by: d.decided_by,
      decided_at: d.decided_at,
      alternatives_considered: d.alternatives_considered || [],
      metadata: d.metadata || %{},
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    }
  end

  def strategy_json(%HydraX.Product.Strategy{} = s) do
    %{
      id: s.id,
      project_id: s.project_id,
      title: s.title,
      body: s.body,
      status: s.status,
      metadata: s.metadata || %{},
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end

  def design_node_json(%HydraX.Product.DesignNode{} = d) do
    %{
      id: d.id,
      project_id: d.project_id,
      title: d.title,
      body: d.body,
      node_type: d.node_type,
      status: d.status,
      metadata: d.metadata || %{},
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    }
  end

  def architecture_node_json(%HydraX.Product.ArchitectureNode{} = a) do
    %{
      id: a.id,
      project_id: a.project_id,
      title: a.title,
      body: a.body,
      node_type: a.node_type,
      status: a.status,
      metadata: a.metadata || %{},
      inserted_at: a.inserted_at,
      updated_at: a.updated_at
    }
  end

  def task_json(%HydraX.Product.Task{} = t) do
    %{
      id: t.id,
      project_id: t.project_id,
      title: t.title,
      body: t.body,
      status: t.status,
      priority: t.priority,
      assignee: t.assignee,
      effort_estimate: t.effort_estimate,
      metadata: t.metadata || %{},
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  def learning_json(%HydraX.Product.Learning{} = l) do
    %{
      id: l.id,
      project_id: l.project_id,
      title: l.title,
      body: l.body,
      learning_type: l.learning_type,
      status: l.status,
      metadata: l.metadata || %{},
      inserted_at: l.inserted_at,
      updated_at: l.updated_at
    }
  end

  def constraint_json(%HydraX.Product.Constraint{} = c) do
    %{
      id: c.id,
      project_id: c.project_id,
      title: c.title,
      body: c.body,
      scope: c.scope,
      enforcement: c.enforcement,
      status: c.status,
      metadata: c.metadata || %{},
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  def routine_json(%HydraX.Product.Routine{} = r) do
    %{
      id: r.id,
      project_id: r.project_id,
      title: r.title,
      description: r.description,
      prompt_template: r.prompt_template,
      assigned_persona: r.assigned_persona,
      schedule_type: r.schedule_type,
      cron_expression: r.cron_expression,
      event_trigger: r.event_trigger,
      timezone: r.timezone,
      output_target: r.output_target,
      status: r.status,
      last_run_at: r.last_run_at,
      last_run_status: r.last_run_status,
      last_run_tokens: r.last_run_tokens,
      metadata: r.metadata || %{},
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

  def knowledge_entry_json(%HydraX.Product.KnowledgeEntry{} = k) do
    %{
      id: k.id,
      project_id: k.project_id,
      title: k.title,
      content: k.content,
      entry_type: k.entry_type,
      assigned_personas: k.assigned_personas,
      source_type: k.source_type,
      source_url: k.source_url,
      status: k.status,
      metadata: k.metadata || %{},
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
      Map.has_key?(node, :node_type) -> Map.put(base, :node_type, node.node_type)
      Map.has_key?(node, :priority) -> Map.merge(base, %{priority: node.priority, assignee: node.assignee, effort_estimate: node.effort_estimate})
      Map.has_key?(node, :decided_by) -> Map.merge(base, %{decided_by: node.decided_by, decided_at: node.decided_at, alternatives_considered: node.alternatives_considered})
      Map.has_key?(node, :learning_type) -> Map.put(base, :learning_type, node.learning_type)
      true -> base
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

  defp loaded_assoc(struct, key) do
    case Map.get(struct, key) do
      %Ecto.Association.NotLoaded{} -> []
      values when is_list(values) -> values
      nil -> []
    end
  end
end
