defmodule HydraXWeb.ProductRealtimePayload do
  @moduledoc false

  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Product.Source
  alias HydraXWeb.ProductConversationPayload
  alias HydraXWeb.ProductPayload

  def project_join_json(project, counts) do
    %{
      project: ProductPayload.project_json(project),
      counts: counts
    }
  end

  def project_event_json(event, %HydraX.Product.Project{} = project)
      when event in ["project.updated", "project.deleted"] do
    %{project: ProductPayload.project_json(project)}
  end

  def project_event_json(event, %Source{} = source)
      when event in ["source.created", "source.updated", "source.deleted"] do
    %{source: ProductPayload.source_json(source)}
  end

  def project_event_json(event, payload)
      when event in ["source.progress", "source.completed", "source.failed"] do
    source = Map.fetch!(payload, :source)

    %{
      source: ProductPayload.source_json(source),
      status: payload[:status],
      stage: payload[:stage],
      chunk_count: payload[:chunk_count],
      error: payload[:error]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def project_event_json(event, %HydraX.Graph.Node{type_key: "insight"} = insight)
      when event in ["insight.created", "insight.updated", "insight.deleted"] do
    %{insight: ProductPayload.insight_json(insight)}
  end

  def project_event_json(event, %HydraX.Graph.Node{type_key: "requirement"} = requirement)
      when event in ["requirement.created", "requirement.updated", "requirement.deleted"] do
    %{requirement: ProductPayload.requirement_json(requirement)}
  end

  def project_event_json(event, %ProductConversation{} = conversation)
      when event in ["conversation.created", "conversation.updated"] do
    %{conversation: ProductConversationPayload.conversation_json(conversation)}
  end

  def project_event_json("message.created", %{conversation: conversation, message: message})
      when is_struct(conversation, ProductConversation) and is_struct(message, ProductMessage) do
    %{
      conversation: ProductConversationPayload.conversation_json(conversation),
      message: ProductConversationPayload.message_json(message)
    }
  end

  def project_event_json("agent_task." <> _ = _event, payload) when is_map(payload) do
    task = Map.get(payload, :task) || Map.get(payload, "task")

    base =
      case task do
        %HydraX.Product.AgentTask{} = t -> %{task: ProductPayload.agent_task_json(t)}
        _ -> %{}
      end

    payload
    |> Map.drop([:task, "task"])
    |> Map.new(fn {k, v} -> {to_atom(k), v} end)
    |> Map.merge(base)
  end

  def project_event_json("flow." <> _, %{flow: flow}) do
    %{flow: flow_json(flow)}
  end

  def project_event_json("mention." <> _, %{mention: mention}) do
    %{mention: mention_json(mention)}
  end

  def project_event_json("stream_entry." <> _, %{stream_entry: entry}) do
    %{stream_entry: stream_entry_json(entry)}
  end

  def project_event_json("contradiction." <> _, %{contradiction: contradiction}) do
    %{contradiction: contradiction_json(contradiction)}
  end

  # Fallback — ignore unknown events rather than crash the channel.
  def project_event_json(_event, _payload), do: %{}

  defp flow_json(%HydraX.Product.Flow{} = flow) do
    %{
      id: flow.id,
      project_id: flow.project_id,
      name: flow.name,
      originating_task_id: flow.originating_task_id,
      status: flow.status,
      participating_agent_ids: flow.participating_agent_ids,
      task_ids: flow.task_ids,
      completed_at: flow.completed_at,
      inserted_at: flow.inserted_at,
      updated_at: flow.updated_at
    }
  end

  defp mention_json(%HydraX.Product.Mention{} = m) do
    %{
      id: m.id,
      project_id: m.project_id,
      source_type: m.source_type,
      source_task_id: m.source_task_id,
      source_agent_id: m.source_agent_id,
      target_agent_id: m.target_agent_id,
      target_task_id: m.target_task_id,
      intent: m.intent,
      content: m.content,
      metadata: m.metadata || %{},
      inserted_at: m.inserted_at
    }
  end

  defp contradiction_json(%HydraX.Coherence.Contradiction{} = c) do
    %{
      id: c.id,
      project_id: c.project_id,
      mode: c.mode,
      severity: c.severity,
      confidence: c.confidence,
      status: c.status,
      explanation: c.explanation,
      node_a: %{type: c.node_a_type, id: c.node_a_id, scope: c.node_a_scope},
      node_b: %{type: c.node_b_type, id: c.node_b_id, scope: c.node_b_scope},
      detected_at: c.detected_at,
      last_confirmed_at: c.last_confirmed_at,
      dismissed_count: c.dismissed_count
    }
  end

  defp stream_entry_json(%HydraX.Product.StreamEntry{} = e) do
    %{
      id: e.id,
      project_id: e.project_id,
      tab: e.tab,
      source_task_id: e.source_task_id,
      source_agent_id: e.source_agent_id,
      title: e.title,
      summary: e.summary,
      context_type: e.context_type,
      context_id: e.context_id,
      read_at: e.read_at,
      actioned_at: e.actioned_at,
      inserted_at: e.inserted_at
    }
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom(k) when is_binary(k), do: String.to_atom(k)

  def source_event_json(event, payload)
      when event in ["progress", "completed", "failed", "deleted"] do
    source = Map.fetch!(payload, :source)

    %{
      source: ProductPayload.source_json(source, true),
      status: payload[:status],
      stage: payload[:stage],
      chunk_count: payload[:chunk_count],
      error: payload[:error]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
