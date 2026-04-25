defmodule HydraXWeb.StreamEntryAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.StreamEntries

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    entries =
      StreamEntries.list_for_project(project_id,
        tab: params["tab"],
        unread: params["unread"] == "true"
      )
      |> Enum.map(&serialize/1)

    json(conn, %{data: entries})
  end

  def counts(conn, %{"project_id" => project_id}) do
    counts = StreamEntries.unread_counts(project_id)

    json(conn, %{
      data: %{
        activity: Map.get(counts, "activity", 0),
        needs_you: Map.get(counts, "needs_you", 0),
        blockers: Map.get(counts, "blockers", 0),
        total: counts |> Map.values() |> Enum.sum()
      }
    })
  end

  def mark_read(conn, %{"project_id" => project_id, "ids" => ids}) when is_list(ids) do
    {count, _} = StreamEntries.mark_read(project_id, ids)
    json(conn, %{data: %{marked: count}})
  end

  def dismiss(conn, %{"project_id" => project_id, "id" => id}) do
    {:ok, count} = StreamEntries.mark_actioned(project_id, id)
    json(conn, %{data: %{actioned: count}})
  end

  defp serialize(entry) do
    %{
      id: entry.id,
      project_id: entry.project_id,
      tab: entry.tab,
      source_task_id: entry.source_task_id,
      source_agent_id: entry.source_agent_id,
      title: entry.title,
      summary: entry.summary,
      context_type: entry.context_type,
      context_id: entry.context_id,
      read_at: entry.read_at,
      actioned_at: entry.actioned_at,
      inserted_at: entry.inserted_at
    }
  end
end
