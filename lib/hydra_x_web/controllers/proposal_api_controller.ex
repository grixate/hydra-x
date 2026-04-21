defmodule HydraXWeb.ProposalAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.AgentTasks
  alias HydraX.Product.Proposals
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    proposals =
      project_id
      |> Proposals.list_proposals(agent_id: params["agent_id"])
      |> Enum.map(&ProductPayload.agent_task_json/1)

    json(conn, %{data: proposals})
  end

  def record(conn, %{"project_id" => project_id, "id" => id, "decisions" => decisions}) do
    task = AgentTasks.get_task!(project_id, id)

    case Proposals.record_item_decisions(task, decisions) do
      {:ok, updated} ->
        json(conn, %{data: ProductPayload.agent_task_json(updated)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", reason: inspect(reason)})
    end
  end

  def apply(conn, %{"project_id" => project_id, "id" => id}) do
    task = AgentTasks.get_task!(project_id, id)

    case Proposals.apply_decisions(task) do
      {:ok, updated} ->
        json(conn, %{data: ProductPayload.agent_task_json(updated)})

      {:error, :no_decisions} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no_decisions"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", reason: inspect(reason)})
    end
  end

  def dismiss(conn, %{"project_id" => project_id, "id" => id} = params) do
    task = AgentTasks.get_task!(project_id, id)

    case Proposals.dismiss(task, reason: params["reason"]) do
      {:ok, updated} ->
        json(conn, %{data: ProductPayload.agent_task_json(updated)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", reason: inspect(reason)})
    end
  end
end
