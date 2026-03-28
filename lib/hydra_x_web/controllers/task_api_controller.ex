defmodule HydraXWeb.TaskAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Task, as: ProductTask
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    tasks =
      Product.list_tasks(project_id,
        status: conn.params["status"],
        priority: conn.params["priority"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.task_json/1)

    json(conn, %{data: tasks})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    task = project_id |> Product.get_project_task!(id) |> ProductPayload.task_json()
    json(conn, %{data: task})
  end

  def create(conn, %{"project_id" => project_id, "task" => params}) do
    with {:ok, %ProductTask{} = task} <- Product.create_task(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.task_json(task)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "task" => params}) do
    task = Product.get_project_task!(project_id, id)
    with {:ok, %ProductTask{} = updated} <- Product.update_task(task, params) do
      json(conn, %{data: ProductPayload.task_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    task = Product.get_project_task!(project_id, id)
    with {:ok, %ProductTask{}} <- Product.delete_task(task) do
      send_resp(conn, :no_content, "")
    end
  end
end
