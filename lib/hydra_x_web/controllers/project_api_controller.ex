defmodule HydraXWeb.ProjectAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Project
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, params) do
    projects =
      Product.list_projects(status: params["status"], search: params["search"])
      |> Enum.map(&ProductPayload.project_json/1)

    json(conn, %{data: projects})
  end

  def show(conn, %{"id" => id}) do
    project =
      id
      |> String.to_integer()
      |> Product.get_project!()
      |> ProductPayload.project_json()

    json(conn, %{data: project})
  end

  def create(conn, %{"project" => params}) do
    with {:ok, %Project{} = project} <- Product.create_project(params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.project_json(project)})
    end
  end

  def update(conn, %{"id" => id, "project" => params}) do
    project =
      id
      |> String.to_integer()
      |> Product.get_project!()

    with {:ok, %Project{} = updated} <- Product.update_project(project, params) do
      json(conn, %{data: ProductPayload.project_json(updated)})
    end
  end

  def counts(conn, %{"project_id" => project_id}) do
    counts = Product.project_counts(project_id)
    json(conn, %{data: counts})
  end

  def delete(conn, %{"id" => id}) do
    project =
      id
      |> String.to_integer()
      |> Product.get_project!()

    with {:ok, %Project{}} <- Product.delete_project(project) do
      send_resp(conn, :no_content, "")
    end
  end
end
