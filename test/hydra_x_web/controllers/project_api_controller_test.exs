defmodule HydraXWeb.ProjectAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Product
  alias HydraX.Runtime
  alias HydraXWeb.OperatorAuth

  test "GET /api/v1/projects requires operator auth when a password is configured", %{conn: conn} do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    conn = get(conn, ~p"/api/v1/projects")

    assert json_response(conn, 401) == %{"error" => "operator_auth_required"}
  end

  test "POST /api/v1/projects provisions a project and returns agent metadata", %{conn: conn} do
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
      |> post(~p"/api/v1/projects", %{
        "project" => %{
          "name" => "Evidence Graph",
          "description" => "Research-core MVP"
        }
      })

    body = json_response(conn, 201)

    assert body["data"]["slug"] == "evidence-graph"
    assert body["data"]["researcher_agent"]["role"] == "researcher"
    assert body["data"]["strategist_agent"]["role"] == "planner"

    project = Product.get_project!(body["data"]["id"])
    assert project.researcher_agent.slug == "project-evidence-graph-researcher"
    assert project.strategist_agent.slug == "project-evidence-graph-strategist"
  end

  test "GET /api/v1/projects lists provisioned projects", %{conn: conn} do
    assert {:ok, _project} = Product.create_project(%{"name" => "Grounded Search"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/v1/projects")

    body = json_response(conn, 200)
    assert Enum.any?(body["data"], &(&1["slug"] == "grounded-search"))
  end

  test "GET /api/v1/projects filters by status and search", %{conn: conn} do
    assert {:ok, active} = Product.create_project(%{"name" => "Grounded Search"})
    assert {:ok, archived} = Product.create_project(%{"name" => "Archived Research"})
    assert {:ok, _archived} = Product.update_project(archived, %{"status" => "archived"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/v1/projects?status=active&search=Grounded")

    body = json_response(conn, 200)

    assert Enum.map(body["data"], & &1["id"]) == [active.id]
  end

  test "PATCH /api/v1/projects/:id updates project status", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Project Update"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> patch(~p"/api/v1/projects/#{project.id}", %{
        "project" => %{"status" => "archived", "description" => "Archived for cleanup"}
      })

    body = json_response(conn, 200)

    assert body["data"]["status"] == "archived"
    assert body["data"]["description"] == "Archived for cleanup"
  end

  test "DELETE /api/v1/projects/:id removes the project", %{conn: conn} do
    {:ok, project} = Product.create_project(%{"name" => "Project Delete"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> delete(~p"/api/v1/projects/#{project.id}")

    assert response(conn, 204)
    assert_raise Ecto.NoResultsError, fn -> Product.get_project!(project.id) end
  end
end
