defmodule HydraXWeb.LearningAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Learning
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    learnings =
      Product.list_learnings(project_id,
        status: conn.params["status"],
        learning_type: conn.params["learning_type"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.learning_json/1)

    json(conn, %{data: learnings})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    learning = project_id |> Product.get_project_learning!(id) |> ProductPayload.learning_json()
    json(conn, %{data: learning})
  end

  def create(conn, %{"project_id" => project_id, "learning" => params}) do
    with {:ok, %Learning{} = learning} <- Product.create_learning(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.learning_json(learning)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "learning" => params}) do
    learning = Product.get_project_learning!(project_id, id)
    with {:ok, %Learning{} = updated} <- Product.update_learning(learning, params) do
      json(conn, %{data: ProductPayload.learning_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    learning = Product.get_project_learning!(project_id, id)
    with {:ok, %Learning{}} <- Product.delete_learning(learning) do
      send_resp(conn, :no_content, "")
    end
  end
end
