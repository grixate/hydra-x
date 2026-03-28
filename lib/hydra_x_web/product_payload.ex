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
