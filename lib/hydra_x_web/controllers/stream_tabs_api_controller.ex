defmodule HydraXWeb.StreamTabsAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.StreamTabs

  action_fallback HydraXWeb.ProjectAPIFallbackController

  @valid_tabs ~w(activity needs_you blockers)

  def index(conn, %{"project_id" => project_id, "tab" => tab} = params) when tab in @valid_tabs do
    items =
      case tab do
        "activity" ->
          StreamTabs.list_activity(project_id,
            agent_id: params["agent_id"],
            search: params["search"]
          )

        "needs_you" ->
          StreamTabs.list_needs_you(project_id)

        "blockers" ->
          StreamTabs.list_blockers(project_id)
      end

    json(conn, %{data: Enum.map(items, &serialize/1)})
  end

  def index(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "invalid_tab"})
  end

  def counts(conn, %{"project_id" => project_id}) do
    counts = StreamTabs.counts(project_id)
    default = StreamTabs.default_tab(project_id)

    json(conn, %{
      data: %{
        activity: counts.activity,
        needs_you: counts.needs_you,
        blockers: counts.blockers,
        default_tab: default
      }
    })
  end

  defp serialize(item) do
    %{
      id: item.id,
      tab: item.tab,
      kind: item.kind,
      title: item.title,
      summary: item.summary,
      actor_agent_id: item.actor_agent_id,
      age_seconds: item.age_seconds,
      source_task_id: item.source_task_id,
      stream_entry_id: item.stream_entry_id,
      flow_id: item.flow_id,
      context_type: item.context_type,
      context_id: item.context_id,
      state: item.state,
      severity: item.severity,
      inserted_at: item.inserted_at
    }
  end
end
