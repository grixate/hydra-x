defmodule HydraXWeb.ProductConversationPayload do
  @moduledoc false

  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Runtime

  def conversation_json(%ProductConversation{} = conversation, opts \\ []) do
    include_messages? = Keyword.get(opts, :include_messages?, false)
    state = Runtime.conversation_channel_state(conversation.hydra_conversation_id)
    messages = loaded_messages(conversation)
    latest_message = List.last(messages)

    %{
      id: conversation.id,
      project_id: conversation.project_id,
      hydra_conversation_id: conversation.hydra_conversation_id,
      persona: conversation.persona,
      title: conversation.title,
      status: conversation.status,
      metadata: conversation.metadata || %{},
      hydra_channel: conversation.hydra_conversation && conversation.hydra_conversation.channel,
      hydra_external_ref:
        conversation.hydra_conversation && conversation.hydra_conversation.external_ref,
      message_count: length(messages),
      latest_message: if(latest_message, do: message_json(latest_message), else: nil),
      channel_state: %{
        status: state.status,
        provider: state.provider,
        tool_rounds: state.tool_rounds,
        resumable: state.resumable
      },
      messages: if(include_messages?, do: Enum.map(messages, &message_json/1), else: nil),
      inserted_at: conversation.inserted_at,
      updated_at: conversation.updated_at
    }
  end

  def message_json(%ProductMessage{} = message) do
    %{
      id: message.id,
      hydra_turn_id: message.hydra_turn_id,
      role: message.role,
      content: message.content,
      citations: message.citations || [],
      metadata: message.metadata || %{},
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
    }
  end

  defp loaded_messages(conversation) do
    case conversation.product_messages do
      %Ecto.Association.NotLoaded{} -> []
      messages -> messages || []
    end
  end
end
