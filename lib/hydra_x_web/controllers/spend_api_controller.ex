defmodule HydraXWeb.SpendAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.SpendAnalytics

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def summary(conn, %{"project_id" => project_id}) do
    data = SpendAnalytics.project_summary(parse_int(project_id))
    json(conn, %{data: data})
  end

  def analytics(conn, %{"project_id" => project_id} = params) do
    project_id = parse_int(project_id)
    now = DateTime.utc_now()

    {period_start, days} =
      case {params["from"], params["to"]} do
        {from, to} when is_binary(from) and is_binary(to) ->
          with {:ok, from_date} <- Date.from_iso8601(from),
               {:ok, to_date} <- Date.from_iso8601(to) do
            {:ok, from_dt} = NaiveDateTime.new(from_date, ~T[00:00:00])
            {DateTime.from_naive!(from_dt, "Etc/UTC"), Date.diff(to_date, from_date) + 1}
          else
            _ -> period_range(params["period"], now)
          end

        _ ->
          period_range(params["period"], now)
      end

    summary = SpendAnalytics.project_summary(project_id)
    by_agent = SpendAnalytics.spend_by_agent(project_id, period_start, now)
    by_model = SpendAnalytics.spend_by_model(project_id, period_start, now)
    daily = SpendAnalytics.daily_spend(project_id, days)

    json(conn, %{
      data: %{
        summary: summary,
        spend_by_agent: by_agent,
        spend_by_model: by_model,
        daily_spend: daily
      }
    })
  end

  def log(conn, %{"project_id" => project_id}) do
    limit = safe_parse_int(conn.params["limit"], 25)
    offset = safe_parse_int(conn.params["offset"], 0)
    {entries, total} = SpendAnalytics.recent_log(parse_int(project_id), min(limit, 100), offset)
    json(conn, %{data: %{entries: entries, total: total, limit: limit, offset: offset}})
  end

  defp period_range("7d", now), do: {DateTime.add(now, -7 * 86400), 7}
  defp period_range("90d", now), do: {DateTime.add(now, -90 * 86400), 90}

  defp period_range(_, _now) do
    today = Date.utc_today()
    {:ok, dt} = NaiveDateTime.new(today.year, today.month, 1, 0, 0, 0)

    {DateTime.from_naive!(dt, "Etc/UTC"),
     Date.diff(Date.utc_today(), Date.new!(today.year, today.month, 1)) + 1}
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)

  defp safe_parse_int(nil, default), do: default

  defp safe_parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp safe_parse_int(v, _default) when is_integer(v), do: v
end
