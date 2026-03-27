defmodule HydraXWeb.ProductConversationAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.AgentBridge
  alias HydraX.Product.ProductConversation
  alias HydraXWeb.ProductConversationPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    conversations =
      AgentBridge.list_project_conversations(
        project_id,
        persona: params["persona"],
        status: params["status"],
        search: params["search"]
      )
      |> Enum.map(&ProductConversationPayload.conversation_json(&1))

    json(conn, %{data: conversations})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    conversation =
      project_id
      |> AgentBridge.get_project_conversation!(id)
      |> ProductConversationPayload.conversation_json(include_messages?: true)

    json(conn, %{data: conversation})
  end

  def create(conn, %{"project_id" => project_id, "conversation" => params}) do
    persona = params["persona"] || "researcher"

    with {:ok, %ProductConversation{} = conversation} <-
           AgentBridge.ensure_project_conversation(project_id, persona, params) do
      refreshed = AgentBridge.get_project_conversation!(project_id, conversation.id)

      conn
      |> put_status(:created)
      |> json(%{
        data: ProductConversationPayload.conversation_json(refreshed, include_messages?: true)
      })
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "conversation" => params}) do
    with {:ok, %ProductConversation{} = conversation} <-
           AgentBridge.update_project_conversation(project_id, id, params) do
      json(conn, %{
        data: ProductConversationPayload.conversation_json(conversation, include_messages?: true)
      })
    end
  end

  def create_message(conn, %{"project_id" => project_id, "id" => id, "message" => params}) do
    conversation = AgentBridge.get_project_conversation!(project_id, id)

    with {:ok, result} <-
           AgentBridge.submit_message(
             conversation,
             params["content"] || "",
             params["metadata"] || %{}
           ) do
      refreshed = AgentBridge.get_project_conversation!(project_id, conversation.id)

      json(conn, %{
        data: %{
          conversation:
            ProductConversationPayload.conversation_json(refreshed, include_messages?: true),
          response: normalize_bridge_response(result.response)
        }
      })
    end
  end

  defp normalize_bridge_response({:deferred, message}) do
    %{status: "deferred", message: message}
  end

  defp normalize_bridge_response(response) when is_binary(response) do
    %{status: "completed", content: response}
  end

  defp normalize_bridge_response(other) do
    %{status: "completed", content: inspect(other, printable_limit: 120)}
  end
end
