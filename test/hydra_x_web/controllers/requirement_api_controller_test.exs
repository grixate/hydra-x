defmodule HydraXWeb.RequirementAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Product

  test "POST /api/v1/projects/:project_id/requirements creates grounded requirements from insights",
       %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Requirement API"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Interview",
        "content" => "Teams need launch review workflows before release."
      })

    chunk = hd(source.source_chunks)

    {:ok, insight} =
      Product.create_insight(project, %{
        "title" => "Launch Workflows",
        "body" => "Teams need launch review workflows before release.",
        "evidence_chunk_ids" => [chunk.id],
        "status" => "accepted"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/requirements", %{
        "requirement" => %{
          "title" => "Support Launch Reviews",
          "body" => "The product must support pre-release launch review workflows.",
          "insight_ids" => [insight.id],
          "status" => "accepted"
        }
      })

    body = json_response(conn, 201)

    assert body["data"]["grounded"] == true
    assert body["data"]["status"] == "accepted"
    assert length(body["data"]["insights"]) == 1
  end

  test "PATCH /api/v1/projects/:project_id/requirements/:id rejects accepting ungrounded requirements",
       %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Requirement Update API"})

    {:ok, requirement} =
      Product.create_requirement(project, %{
        "title" => "Manual Notes",
        "body" => "This is ungrounded.",
        "status" => "draft"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> patch(~p"/api/v1/projects/#{project.id}/requirements/#{requirement.id}", %{
        "requirement" => %{"status" => "accepted"}
      })

    body = json_response(conn, 422)
    assert body["error"] == "validation_failed"
  end

  test "GET /api/v1/projects/:project_id/requirements filters by status, grounded, and search",
       %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Requirement Filter API"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Interview",
        "content" => "Teams need launch review workflows before release."
      })

    chunk = hd(source.source_chunks)

    {:ok, insight} =
      Product.create_insight(project, %{
        "title" => "Launch Workflows",
        "body" => "Teams need launch review workflows before release.",
        "evidence_chunk_ids" => [chunk.id],
        "status" => "accepted"
      })

    {:ok, _grounded} =
      Product.create_requirement(project, %{
        "title" => "Support Launch Reviews",
        "body" => "The product must support pre-release launch review workflows.",
        "insight_ids" => [insight.id],
        "status" => "accepted"
      })

    {:ok, _draft} =
      Product.create_requirement(project, %{
        "title" => "Backlog Notes",
        "body" => "Document ungrounded backlog ideas.",
        "status" => "draft"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(
        ~p"/api/v1/projects/#{project.id}/requirements?status=accepted&grounded=true&search=Launch"
      )

    body = json_response(conn, 200)

    assert Enum.map(body["data"], & &1["title"]) == ["Support Launch Reviews"]
  end

  test "DELETE /api/v1/projects/:project_id/requirements/:id removes the requirement",
       %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Requirement Delete API"})

    {:ok, requirement} =
      Product.create_requirement(project, %{
        "title" => "Delete Requirement",
        "body" => "Remove this requirement.",
        "status" => "draft"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> delete(~p"/api/v1/projects/#{project.id}/requirements/#{requirement.id}")

    assert response(conn, 204)

    assert_raise Ecto.NoResultsError, fn ->
      Product.get_project_requirement!(project, requirement.id)
    end
  end
end
