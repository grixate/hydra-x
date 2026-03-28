defmodule HydraXWeb.ConstraintAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Constraint
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    constraints =
      Product.list_constraints(project_id, status: conn.params["status"])
      |> Enum.map(&ProductPayload.constraint_json/1)

    json(conn, %{data: constraints})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    constraint = project_id |> Product.get_project_constraint!(id) |> ProductPayload.constraint_json()
    json(conn, %{data: constraint})
  end

  def create(conn, %{"project_id" => project_id, "constraint" => params}) do
    with {:ok, %Constraint{} = constraint} <- Product.create_constraint(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.constraint_json(constraint)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "constraint" => params}) do
    constraint = Product.get_project_constraint!(project_id, id)
    with {:ok, %Constraint{} = updated} <- Product.update_constraint(constraint, params) do
      json(conn, %{data: ProductPayload.constraint_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    constraint = Product.get_project_constraint!(project_id, id)
    with {:ok, %Constraint{}} <- Product.delete_constraint(constraint) do
      send_resp(conn, :no_content, "")
    end
  end
end
