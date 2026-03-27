defmodule HydraXWeb.ProductConversationChannel do
  use HydraXWeb, :channel

  alias HydraX.Product
  alias HydraX.Product.AgentBridge
  alias HydraXWeb.ProductChannelAuth
  alias HydraXWeb.ProductConversationPayload

  @impl true
  def join("product_conversation:" <> raw_id, _params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         :ok <- ProductChannelAuth.allow_sandbox(socket),
         conversation <- Product.get_product_conversation!(conversation_id(raw_id)) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations")
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations:stream")

      {:ok,
       %{
         conversation:
           ProductConversationPayload.conversation_json(conversation, include_messages?: true)
       },
       assign(socket,
         product_conversation_id: conversation.id,
         hydra_conversation_id: conversation.hydra_conversation_id
       )}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  rescue
    Ecto.NoResultsError -> {:error, %{reason: "not_found"}}
  end

  @impl true
  def handle_in("message:create", %{"content" => content} = params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         {:ok, result} <-
           AgentBridge.submit_message(
             socket.assigns.product_conversation_id,
             content,
             params["metadata"] || %{}
           ) do
      refreshed = Product.get_product_conversation!(socket.assigns.product_conversation_id)

      {:reply,
       {:ok,
        %{
          conversation:
            ProductConversationPayload.conversation_json(refreshed, include_messages?: true),
          response: normalize_bridge_response(result.response)
        }}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: format_reason(reason)}}, socket}
    end
  end

  def handle_in("conversation:update", params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         conversation <- Product.get_product_conversation!(socket.assigns.product_conversation_id),
         {:ok, updated} <-
           AgentBridge.update_project_conversation(
             conversation.project_id,
             conversation.id,
             params
           ) do
      {:reply,
       {:ok,
        %{
          conversation:
            ProductConversationPayload.conversation_json(updated, include_messages?: true)
        }}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: format_reason(reason)}}, socket}
    end
  end

  def handle_in("sync", _params, socket) do
    conversation = Product.get_product_conversation!(socket.assigns.product_conversation_id)

    {:reply,
     {:ok,
      %{
        conversation:
          ProductConversationPayload.conversation_json(conversation, include_messages?: true)
      }}, socket}
  end

  @impl true
  def handle_info({:stream_chunk, hydra_conversation_id, delta}, socket)
      when hydra_conversation_id == socket.assigns.hydra_conversation_id do
    push(socket, "stream_chunk", %{
      hydra_conversation_id: hydra_conversation_id,
      delta: delta
    })

    {:noreply, socket}
  end

  def handle_info({:stream_done, hydra_conversation_id}, socket)
      when hydra_conversation_id == socket.assigns.hydra_conversation_id do
    conversation = Product.get_product_conversation!(socket.assigns.product_conversation_id)

    push(socket, "stream_done", %{
      hydra_conversation_id: hydra_conversation_id,
      conversation:
        ProductConversationPayload.conversation_json(conversation, include_messages?: true)
    })

    {:noreply, socket}
  end

  def handle_info({:conversation_updated, hydra_conversation_id}, socket)
      when hydra_conversation_id == socket.assigns.hydra_conversation_id do
    conversation = Product.get_product_conversation!(socket.assigns.product_conversation_id)

    push(socket, "conversation_updated", %{
      hydra_conversation_id: hydra_conversation_id,
      conversation:
        ProductConversationPayload.conversation_json(conversation, include_messages?: true)
    })

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp conversation_id(raw_id), do: String.to_integer(raw_id)

  defp normalize_bridge_response({:deferred, message}) do
    %{status: "deferred", message: message}
  end

  defp normalize_bridge_response(response) when is_binary(response) do
    %{status: "completed", content: response}
  end

  defp normalize_bridge_response(other) do
    %{status: "completed", content: inspect(other, printable_limit: 120)}
  end

  defp format_reason({:tool_disabled_by_policy, tool_name, _channel}),
    do: "tool_disabled:#{tool_name}"

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
