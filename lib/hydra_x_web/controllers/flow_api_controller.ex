defmodule HydraXWeb.FlowAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.Flows
  alias HydraX.Product.Mentions

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    flows =
      project_id
      |> Flows.list_active()
      |> Enum.map(&serialize/1)

    json(conn, %{data: flows})
  end

  def create_mention(conn, %{"project_id" => project_id, "mention" => attrs}) do
    attrs =
      attrs
      |> Map.put_new("project_id", String.to_integer(to_string(project_id)))
      |> Map.put_new("source_type", "task")

    case Mentions.create_mention(attrs) do
      {:ok, mention} ->
        conn
        |> put_status(:created)
        |> json(%{data: serialize_mention(mention)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", details: format_errors(changeset)})
    end
  end

  defp serialize(flow) do
    %{
      id: flow.id,
      project_id: flow.project_id,
      name: flow.name,
      originating_task_id: flow.originating_task_id,
      status: flow.status,
      participating_agent_ids: flow.participating_agent_ids,
      task_ids: flow.task_ids,
      completed_at: flow.completed_at,
      inserted_at: flow.inserted_at,
      updated_at: flow.updated_at
    }
  end

  def update_intent(conn, %{"project_id" => _project_id, "id" => id, "intent" => intent}) do
    case Mentions.get_mention(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      mention ->
        case Mentions.update_intent(mention, intent) do
          {:ok, updated} ->
            json(conn, %{data: serialize_mention(updated)})

          {:error, :invalid_intent} ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_intent"})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid", details: format_errors(changeset)})
        end
    end
  end

  defp serialize_mention(mention) do
    %{
      id: mention.id,
      project_id: mention.project_id,
      source_type: mention.source_type,
      source_task_id: mention.source_task_id,
      source_agent_id: mention.source_agent_id,
      target_agent_id: mention.target_agent_id,
      target_task_id: mention.target_task_id,
      intent: mention.intent,
      content: mention.content,
      metadata: mention.metadata || %{},
      inserted_at: mention.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
