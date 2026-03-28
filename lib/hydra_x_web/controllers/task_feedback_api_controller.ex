defmodule HydraXWeb.TaskFeedbackAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => _project_id, "task_id" => task_id}) do
    feedback =
      Product.list_task_feedback(task_id)
      |> Enum.map(&ProductPayload.task_feedback_json/1)

    json(conn, %{data: feedback})
  end

  def create(conn, %{"project_id" => _project_id, "task_id" => task_id, "feedback" => params}) do
    case Product.create_task_feedback(task_id, params) do
      {:ok, feedback} ->
        conn |> put_status(:created) |> json(%{data: ProductPayload.task_feedback_json(feedback)})
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end
end
