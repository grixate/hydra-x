defmodule HydraXWeb.ProductRealtimePayload do
  @moduledoc false

  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Product.Requirement
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

  def project_event_json(event, %HydraX.Product.Insight{} = insight)
      when event in ["insight.created", "insight.updated", "insight.deleted"] do
    %{insight: ProductPayload.insight_json(insight)}
  end

  def project_event_json(event, %Requirement{} = requirement)
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
