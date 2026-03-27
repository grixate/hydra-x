defmodule HydraXWeb.ProductConversationChannelTest do
  use HydraXWeb.ChannelCase

  alias HydraX.Product
  alias HydraX.Product.AgentBridge

  test "join returns the current product conversation payload", %{socket: socket} do
    {:ok, project} = Product.create_project(%{"name" => "Channel Join"})

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "channel-join"
      })

    assert {:ok, payload, _socket} =
             subscribe_and_join(
               socket,
               HydraXWeb.ProductConversationChannel,
               "product_conversation:#{conversation.id}"
             )

    assert payload.conversation.id == conversation.id
    assert payload.conversation.persona == "researcher"
  end

  test "channel relays stream and conversation update events for the bound hydra conversation", %{
    socket: socket
  } do
    {:ok, project} = Product.create_project(%{"name" => "Channel Relay"})

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "channel-relay"
      })

    {:ok, _payload, _socket} =
      subscribe_and_join(
        socket,
        HydraXWeb.ProductConversationChannel,
        "product_conversation:#{conversation.id}"
      )

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations:stream",
      {:stream_chunk, conversation.hydra_conversation_id, "partial"}
    )

    assert_push "stream_chunk", %{delta: "partial"}

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations",
      {:conversation_updated, conversation.hydra_conversation_id}
    )

    assert_push "conversation_updated", %{conversation: pushed_conversation}
    assert pushed_conversation.id == conversation.id

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      "conversations:stream",
      {:stream_done, conversation.hydra_conversation_id}
    )

    assert_push "stream_done", %{conversation: done_conversation}
    assert done_conversation.id == conversation.id
  end

  test "message:create submits through the agent bridge and returns the refreshed conversation",
       %{
         socket: socket
       } do
    {:ok, project} = Product.create_project(%{"name" => "Channel Send"})

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "channel-send"
      })

    {:ok, _payload, socket} =
      subscribe_and_join(
        socket,
        HydraXWeb.ProductConversationChannel,
        "product_conversation:#{conversation.id}"
      )

    ref = push(socket, "message:create", %{"content" => "Ground this response."})
    assert_reply ref, :ok, %{conversation: refreshed, response: response}, 1_000

    assert response.status == "completed"
    assert Enum.any?(refreshed.messages, &(&1.content == "Ground this response."))
  end

  test "conversation:update renames and archives the bound product conversation", %{
    socket: socket
  } do
    {:ok, project} = Product.create_project(%{"name" => "Channel Update"})

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "title" => "Mutable Thread",
        "external_ref" => "channel-update"
      })

    {:ok, _payload, socket} =
      subscribe_and_join(
        socket,
        HydraXWeb.ProductConversationChannel,
        "product_conversation:#{conversation.id}"
      )

    ref =
      push(socket, "conversation:update", %{
        "title" => "Archived Mutable Thread",
        "status" => "archived",
        "metadata" => %{"updated_via" => "channel"}
      })

    assert_reply ref, :ok, %{conversation: updated}, 1_000
    assert updated.title == "Archived Mutable Thread"
    assert updated.status == "archived"
    assert updated.metadata["updated_via"] == "channel"

    assert_push "conversation_updated", %{conversation: pushed_conversation}
    assert pushed_conversation.title == "Archived Mutable Thread"
    assert pushed_conversation.status == "archived"
  end
end
