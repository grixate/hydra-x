defmodule HydraXWeb.AgentTaskAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.AgentTasks
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    filters = [
      state: params["state"],
      agent_id: params["agent_id"],
      search: params["search"],
      exclude_terminal: params["exclude_terminal"] == "true"
    ]

    tasks =
      project_id
      |> AgentTasks.list_tasks(filters)
      |> Enum.map(&ProductPayload.agent_task_json/1)

    json(conn, %{data: tasks})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    task = AgentTasks.get_task!(project_id, id)
    json(conn, %{data: ProductPayload.agent_task_json(task)})
  end

  def transition(conn, %{"project_id" => project_id, "id" => id, "to" => to} = params) do
    task = AgentTasks.get_task!(project_id, id)

    case AgentTasks.transition(task, to, reason: params["reason"]) do
      {:ok, updated} ->
        json(conn, %{data: ProductPayload.agent_task_json(updated)})

      {:error, :invalid_transition} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_transition", from: task.state, to: to})

      {:error, :stale} ->
        fresh = AgentTasks.get_task!(task.project_id, task.id)

        conn
        |> put_status(:conflict)
        |> json(%{
          error: "stale",
          message: "Task was updated concurrently. Refresh and retry.",
          data: ProductPayload.agent_task_json(fresh)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", details: format_errors(changeset)})
    end
  end

  def redirect(conn, %{"project_id" => project_id, "id" => id, "refinement" => refinement}) do
    task = AgentTasks.get_task!(project_id, id)

    case AgentTasks.redirect(task, refinement) do
      {:ok, updated} ->
        json(conn, %{data: ProductPayload.agent_task_json(updated)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", details: format_errors(changeset)})
    end
  end

  def defer(conn, %{"project_id" => project_id, "id" => id} = params) do
    hours =
      case params["hours"] do
        h when is_integer(h) and h > 0 ->
          h

        h when is_binary(h) ->
          case Integer.parse(h) do
            {n, _} when n > 0 -> n
            _ -> 24
          end

        _ ->
          24
      end

    task = AgentTasks.get_task!(project_id, id)

    action = if params["clear"] == "true" or params["clear"] == true, do: :clear, else: hours

    case AgentTasks.defer(task, action) do
      {:ok, updated} ->
        json(conn, %{data: ProductPayload.agent_task_json(updated)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", details: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
