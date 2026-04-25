defmodule HydraXWeb.AnalyticsAPIController do
  use HydraXWeb, :controller

  import Ecto.Query

  alias HydraX.Product.Graph, as: ProductGraph
  alias HydraX.Repo

  action_fallback HydraXWeb.ProjectAPIFallbackController

  @node_types ~w(insight decision strategy requirement design_node architecture_node task learning)

  @accepted_statuses ~w(accepted active done)

  def index(conn, %{"project_id" => project_id}) do
    project_id = parse_int(project_id)
    period_start = beginning_of_month()

    productivity = compute_productivity(project_id, period_start)

    summary = HydraX.Product.SpendAnalytics.project_summary(project_id)

    json(conn, %{
      data: %{
        period: "month",
        period_start: Date.to_iso8601(DateTime.to_date(period_start)),
        productivity: productivity,
        spend: %{
          total_tokens: summary.month_tokens,
          total_cost_cents: summary.month_cost_cents,
          projected_cost_cents: 0,
          budget_limit_cents: summary.budget_cents || 5000,
          budget_used_percent: summary.budget_percent || 0
        },
        spend_by_agent: [],
        spend_by_work_type: %{conversational: 0, reactive: 0, autonomous: 0},
        daily_spend: [],
        activity_heatmap: %{},
        this_week: %{cost_cents: summary.week_cost_cents, vs_last_week_percent: 0},
        today: %{cost_cents: summary.today_cost_cents}
      }
    })
  end

  defp compute_productivity(project_id, since) do
    counts =
      Enum.map(@node_types, fn type ->
        case ProductGraph.base_query_for(type) do
          nil ->
            {type, 0, 0}

          query ->
            total =
              query
              |> where([n], n.project_id == ^project_id and n.inserted_at >= ^since)
              |> Repo.aggregate(:count, :id)

            accepted =
              query
              |> where(
                [n],
                n.project_id == ^project_id and n.inserted_at >= ^since and
                  n.status in ^@accepted_statuses
              )
              |> Repo.aggregate(:count, :id)

            {type, total, accepted}
        end
      end)

    total_created = Enum.reduce(counts, 0, fn {_, t, _}, acc -> acc + t end)
    total_accepted = Enum.reduce(counts, 0, fn {_, _, a}, acc -> acc + a end)
    rate = if total_created > 0, do: Float.round(total_accepted / total_created, 2), else: 0.0

    by_type =
      counts
      |> Enum.filter(fn {_, t, _} -> t > 0 end)
      |> Map.new(fn {type, total, _} -> {type, total} end)

    %{
      nodes_created: total_created,
      nodes_accepted: total_accepted,
      acceptance_rate: rate,
      cost_per_accepted_node_cents: 0,
      by_node_type: by_type
    }
  end

  defp beginning_of_month do
    today = Date.utc_today()
    {:ok, dt} = NaiveDateTime.new(today.year, today.month, 1, 0, 0, 0)
    DateTime.from_naive!(dt, "Etc/UTC")
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
