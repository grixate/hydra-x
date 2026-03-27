defmodule HydraXWeb.ProjectChannelTest do
  use HydraXWeb.ChannelCase

  alias HydraX.Product
  alias HydraX.Product.AgentBridge

  test "join returns project metadata and counts", %{socket: socket} do
    {:ok, project} = Product.create_project(%{"name" => "Project Channel Join"})

    {:ok, reply, socket} =
      subscribe_and_join(socket, HydraXWeb.ProjectChannel, "project:#{project.id}")

    assert socket.assigns.project_id == project.id
    assert reply.project.id == project.id
    assert reply.counts == %{sources: 0, insights: 0, requirements: 0, conversations: 0}
  end

  test "project channel relays source, insight, requirement, and conversation events", %{
    socket: socket
  } do
    {:ok, project} = Product.create_project(%{"name" => "Project Channel Events"})

    {:ok, reply, _socket} =
      subscribe_and_join(socket, HydraXWeb.ProjectChannel, "project:#{project.id}")

    assert reply.project.id == project.id
    assert reply.counts == %{sources: 0, insights: 0, requirements: 0, conversations: 0}

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Research Broadcast",
        "content" => "Operators want clearer release readiness reviews each week."
      })

    source_id = source.id

    assert_push "source.created", %{source: %{title: "Research Broadcast"}}
    assert_push "source.progress", %{status: "progress", stage: "chunking"}
    assert_push "source.updated", %{source: %{id: ^source_id, processing_status: "completed"}}

    assert_push "source.completed", %{
      status: "completed",
      source: %{id: ^source_id, processing_status: "completed"}
    }

    source = Product.get_project_source!(project, source.id)
    chunk = hd(source.source_chunks)

    {:ok, insight} =
      Product.create_insight(project, %{
        "title" => "Weekly Review Need",
        "body" => "Operators want clearer weekly release readiness reviews.",
        "evidence_chunk_ids" => [chunk.id]
      })

    insight_id = insight.id

    assert_push "insight.created", %{insight: %{id: ^insight_id, title: "Weekly Review Need"}}

    {:ok, requirement} =
      Product.create_requirement(project, %{
        "title" => "Add Review Summary",
        "body" => "The product must expose a weekly release readiness summary.",
        "insight_ids" => [insight.id]
      })

    requirement_id = requirement.id

    assert_push "requirement.created", %{requirement: %{id: ^requirement_id, grounded: true}}

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "project-channel-events"
      })

    conversation_id = conversation.id

    assert_push "conversation.created", %{conversation: %{id: ^conversation_id}}

    assert {:ok, _result} =
             AgentBridge.submit_message(conversation, "Trace the research findings.")

    assert_push "message.created", %{
      message: %{content: "Trace the research findings.", role: "user"}
    }

    assert_push "conversation.updated", %{conversation: %{id: ^conversation_id}}

    assert {:ok, archived} =
             AgentBridge.update_project_conversation(project, conversation, %{
               "title" => "Archived Project Thread",
               "status" => "archived"
             })

    assert archived.status == "archived"

    assert_push "conversation.updated", %{
      conversation: %{id: ^conversation_id, status: "archived"}
    }

    assert {:ok, deleted_requirement} = Product.delete_requirement(requirement)
    assert deleted_requirement.id == requirement.id
    assert_push "requirement.deleted", %{requirement: %{id: ^requirement_id}}

    assert {:ok, deleted_insight} = Product.delete_insight(insight)
    assert deleted_insight.id == insight.id
    assert_push "insight.deleted", %{insight: %{id: ^insight_id}}

    assert {:ok, deleted_source} = Product.delete_source(source)
    assert deleted_source.id == source.id
    assert_push "source.deleted", %{source: %{id: ^source_id}}
  end

  test "project channel relays project lifecycle updates", %{socket: socket} do
    {:ok, project} = Product.create_project(%{"name" => "Project Channel Lifecycle"})
    project_id = project.id

    {:ok, _reply, _socket} =
      subscribe_and_join(socket, HydraXWeb.ProjectChannel, "project:#{project.id}")

    assert {:ok, archived} =
             Product.update_project(project, %{
               "status" => "archived",
               "description" => "Lifecycle test"
             })

    assert archived.status == "archived"
    assert_push "project.updated", %{project: %{id: ^project_id, status: "archived"}}

    assert {:ok, _deleted} = Product.delete_project(archived)
    assert_push "project.deleted", %{project: %{id: ^project_id}}
  end
end
