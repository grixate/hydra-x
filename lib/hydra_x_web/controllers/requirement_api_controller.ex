defmodule HydraXWeb.RequirementAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Requirement
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    requirements =
      Product.list_requirements(project_id,
        status: conn.params["status"],
        grounded: conn.params["grounded"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.requirement_json/1)

    json(conn, %{data: requirements})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    requirement =
      project_id
      |> Product.get_project_requirement!(id)
      |> ProductPayload.requirement_json()

    json(conn, %{data: requirement})
  end

  def create(conn, %{"project_id" => project_id, "requirement" => params}) do
    with {:ok, %Requirement{} = requirement} <- Product.create_requirement(project_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.requirement_json(requirement)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "requirement" => params}) do
    requirement = Product.get_project_requirement!(project_id, id)

    with {:ok, %Requirement{} = updated} <- Product.update_requirement(requirement, params) do
      json(conn, %{data: ProductPayload.requirement_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    requirement = Product.get_project_requirement!(project_id, id)

    with {:ok, %Requirement{}} <- Product.delete_requirement(requirement) do
      send_resp(conn, :no_content, "")
    end
  end
end
