defmodule HydraXWeb.SourceAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Memory
  alias HydraX.Product
  alias HydraX.Runtime
  alias HydraXWeb.OperatorAuth

  test "POST /api/v1/projects/:project_id/sources indexes source content", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "API Sources"})

    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn =
      conn
      |> init_test_session(%{})
      |> OperatorAuth.log_in()
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/sources", %{
        "source" => %{
          "title" => "Launch Debrief",
          "source_type" => "markdown",
          "content" => """
          ## Risks
          Teams need launch readiness reviews before release windows.

          ## Automation
          Operators want scheduled summaries for unresolved issues.
          """
        }
      })

    body = json_response(conn, 201)

    assert body["data"]["title"] == "Launch Debrief"
    assert body["data"]["processing_status"] == "completed"
    assert body["data"]["source_chunk_count"] >= 2
    assert length(body["data"]["chunks"]) >= 2
  end

  test "GET /api/v1/projects/:project_id/sources lists project sources", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "API Source List"})

    {:ok, _source} =
      Product.create_source(project, %{
        "title" => "Interview 1",
        "content" => "Users want better weekly summaries."
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/v1/projects/#{project.id}/sources")

    body = json_response(conn, 200)

    assert Enum.any?(body["data"], &(&1["title"] == "Interview 1"))
  end

  test "GET /api/v1/projects/:project_id/sources filters by type, status, and search", %{
    conn: conn
  } do
    {:ok, project} = Product.create_project(%{"name" => "API Source Filters"})

    {:ok, _matching} =
      Product.create_source(project, %{
        "title" => "Launch Debrief",
        "source_type" => "markdown",
        "content" => "Teams want launch readiness reviews."
      })

    {:ok, _other} =
      Product.create_source(project, %{
        "title" => "Retention Notes",
        "source_type" => "text",
        "content" => "Users want weekly summaries."
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(
        ~p"/api/v1/projects/#{project.id}/sources?processing_status=completed&source_type=markdown&search=Launch"
      )

    body = json_response(conn, 200)

    assert Enum.map(body["data"], & &1["title"]) == ["Launch Debrief"]
  end

  test "POST /api/v1/projects/:project_id/sources can mirror source chunks into project memory",
       %{
         conn: conn
       } do
    {:ok, project} = Product.create_project(%{"name" => "API Source Memory"})

    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn =
      conn
      |> init_test_session(%{})
      |> OperatorAuth.log_in()
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/projects/#{project.id}/sources", %{
        "source" => %{
          "title" => "Launch Memory Notes",
          "content" => "Operators need a weekly launch summary before release windows.",
          "mirror_to_memory" => true
        }
      })

    body = json_response(conn, 201)
    mirror = body["data"]["metadata"]["memory_mirror"]

    assert mirror["status"] == "completed"
    assert mirror["mirrored_memory_count"] == 2

    assert Enum.any?(
             Memory.list_memories(agent_id: project.researcher_agent_id, limit: 20),
             &(&1.metadata["product_source_title"] == "Launch Memory Notes")
           )
  end

  test "DELETE /api/v1/projects/:project_id/sources/:id removes the source", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "API Source Delete"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Delete Me",
        "content" => "Operators want this removed."
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> delete(~p"/api/v1/projects/#{project.id}/sources/#{source.id}")

    assert response(conn, 204)
    assert_raise Ecto.NoResultsError, fn -> Product.get_project_source!(project, source.id) end
  end
end
