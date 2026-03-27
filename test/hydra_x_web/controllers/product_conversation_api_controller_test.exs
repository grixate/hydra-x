defmodule HydraXWeb.ProductConversationAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Product

  test "POST /api/v1/projects/:project_id/conversations creates a product conversation", %{
    conn: conn
  } do
    {:ok, project} = Product.create_project(%{"name" => "Conversation API"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/conversations", %{
        "conversation" => %{
          "persona" => "researcher",
          "title" => "Research Thread",
          "external_ref" => "conversation-api-thread"
        }
      })

    body = json_response(conn, 201)

    assert body["data"]["persona"] == "researcher"
    assert body["data"]["title"] == "Research Thread"
    assert body["data"]["hydra_channel"] == "product_chat"
  end

  test "POST /api/v1/projects/:project_id/conversations/:id/messages routes through the hydra channel",
       %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Conversation Send API"})

    {:ok, conversation} =
      HydraX.Product.AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "conversation-send-thread"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/conversations/#{conversation.id}/messages", %{
        "message" => %{"content" => "Summarize the latest project grounding."}
      })

    body = json_response(conn, 200)

    assert body["data"]["response"]["status"] == "completed"

    assert Enum.any?(
             body["data"]["conversation"]["messages"],
             &(&1["content"] == "Summarize the latest project grounding.")
           )
  end

  test "PATCH /api/v1/projects/:project_id/conversations/:id updates title and status", %{
    conn: conn
  } do
    {:ok, project} = Product.create_project(%{"name" => "Conversation Update API"})

    {:ok, conversation} =
      HydraX.Product.AgentBridge.ensure_project_conversation(project, :researcher, %{
        "title" => "Original Thread",
        "external_ref" => "conversation-update-thread"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> patch(~p"/api/v1/projects/#{project.id}/conversations/#{conversation.id}", %{
        "conversation" => %{
          "title" => "Archived Research Thread",
          "status" => "archived",
          "metadata" => %{"archived_by" => "operator"}
        }
      })

    body = json_response(conn, 200)
    refreshed = HydraX.Product.AgentBridge.get_project_conversation!(project, conversation.id)
    hydra_conversation = HydraX.Runtime.get_conversation!(conversation.hydra_conversation_id)

    assert body["data"]["title"] == "Archived Research Thread"
    assert body["data"]["status"] == "archived"
    assert body["data"]["metadata"]["archived_by"] == "operator"
    assert refreshed.title == "Archived Research Thread"
    assert refreshed.status == "archived"
    assert hydra_conversation.title == "Archived Research Thread"
    assert hydra_conversation.status == "archived"
  end

  test "GET /api/v1/projects/:project_id/conversations filters by persona, status, and search", %{
    conn: conn
  } do
    {:ok, project} = Product.create_project(%{"name" => "Conversation Filter API"})

    {:ok, matching} =
      HydraX.Product.AgentBridge.ensure_project_conversation(project, :researcher, %{
        "title" => "Launch Research Thread",
        "external_ref" => "conversation-filter-launch"
      })

    {:ok, other} =
      HydraX.Product.AgentBridge.ensure_project_conversation(project, :strategist, %{
        "title" => "Backlog Planning Thread",
        "external_ref" => "conversation-filter-backlog"
      })

    {:ok, _archived} =
      HydraX.Product.AgentBridge.update_project_conversation(project, other, %{
        "status" => "archived"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(
        ~p"/api/v1/projects/#{project.id}/conversations?persona=researcher&status=active&search=Launch"
      )

    body = json_response(conn, 200)

    assert Enum.map(body["data"], & &1["id"]) == [matching.id]
  end

  test "POST /api/v1/projects/:project_id/exports returns a product export bundle", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Conversation Export API"})

    {:ok, _source} =
      Product.create_source(project, %{
        "title" => "Export Source",
        "content" => "Operators need project export bundles."
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/exports", %{})

    body = json_response(conn, 200)

    assert File.exists?(body["data"]["markdown_path"])
    assert File.exists?(body["data"]["json_path"])
    assert File.dir?(body["data"]["bundle_dir"])
  end
end
