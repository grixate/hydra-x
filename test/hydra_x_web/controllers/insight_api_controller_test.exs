defmodule HydraXWeb.InsightAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Product

  test "POST /api/v1/projects/:project_id/insights creates grounded insights", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Insight API"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Call Notes",
        "content" => "Users depend on weekly release summaries."
      })

    chunk = hd(source.source_chunks)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/insights", %{
        "insight" => %{
          "title" => "Weekly Summaries",
          "body" => "Users depend on weekly release summaries.",
          "evidence_chunk_ids" => [chunk.id]
        }
      })

    body = json_response(conn, 201)

    assert body["data"]["title"] == "Weekly Summaries"
    assert length(body["data"]["evidence"]) == 1
    assert hd(body["data"]["evidence"])["source_chunk_id"] == chunk.id
  end

  test "PATCH /api/v1/projects/:project_id/insights/:id updates insight status", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Insight Update API"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Call Notes",
        "content" => "Launch reviews reduce release risk."
      })

    chunk = hd(source.source_chunks)

    {:ok, insight} =
      Product.create_insight(project, %{
        "title" => "Launch Reviews",
        "body" => "Launch reviews reduce release risk.",
        "evidence_chunk_ids" => [chunk.id]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> patch(~p"/api/v1/projects/#{project.id}/insights/#{insight.id}", %{
        "insight" => %{"status" => "accepted"}
      })

    body = json_response(conn, 200)
    assert body["data"]["status"] == "accepted"
  end

  test "GET /api/v1/projects/:project_id/insights filters by status and search", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Insight Filter API"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Research",
        "content" => "Launch reviews reduce release risk and weekly summaries improve trust."
      })

    chunk = hd(source.source_chunks)

    {:ok, _accepted} =
      Product.create_insight(project, %{
        "title" => "Launch Reviews",
        "body" => "Launch reviews reduce release risk.",
        "evidence_chunk_ids" => [chunk.id],
        "status" => "accepted"
      })

    {:ok, _draft} =
      Product.create_insight(project, %{
        "title" => "Weekly Summaries",
        "body" => "Weekly summaries improve trust.",
        "evidence_chunk_ids" => [chunk.id],
        "status" => "draft"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/v1/projects/#{project.id}/insights?status=accepted&search=Launch")

    body = json_response(conn, 200)

    assert Enum.map(body["data"], & &1["title"]) == ["Launch Reviews"]
  end

  test "DELETE /api/v1/projects/:project_id/insights/:id removes the insight", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Insight Delete API"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Call Notes",
        "content" => "Launch reviews reduce release risk."
      })

    chunk = hd(source.source_chunks)

    {:ok, insight} =
      Product.create_insight(project, %{
        "title" => "Delete Insight",
        "body" => "Launch reviews reduce release risk.",
        "evidence_chunk_ids" => [chunk.id]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> delete(~p"/api/v1/projects/#{project.id}/insights/#{insight.id}")

    assert response(conn, 204)
    assert_raise Ecto.NoResultsError, fn -> Product.get_project_insight!(project, insight.id) end
  end
end
