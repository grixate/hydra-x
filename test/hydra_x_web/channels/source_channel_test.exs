defmodule HydraXWeb.SourceChannelTest do
  use HydraXWeb.ChannelCase

  alias HydraX.Product
  alias HydraX.Product.PubSub, as: ProductPubSub

  test "join returns the current source payload and relays source events", %{socket: socket} do
    {:ok, project} = Product.create_project(%{"name" => "Source Channel Join"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Source Channel Notes",
        "content" => "Customers want a clearer evidence panel for every finding."
      })

    {:ok, reply, _socket} =
      subscribe_and_join(socket, HydraXWeb.SourceChannel, "source:#{source.id}")

    source_id = source.id

    assert reply.source.id == source.id
    assert reply.source.title == "Source Channel Notes"
    assert reply.source.processing_status == "completed"
    assert reply.source.source_chunk_count >= 1

    ProductPubSub.broadcast_source_progress(source, "progress", %{stage: "embedding"})

    assert_push "progress", %{
      status: "progress",
      stage: "embedding",
      source: %{id: ^source_id}
    }

    assert {:ok, deleted} = Product.delete_source(source)
    assert deleted.id == source.id
    assert_push "deleted", %{source: %{id: ^source_id}}
  end
end
