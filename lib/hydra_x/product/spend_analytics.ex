defmodule HydraX.Product.SpendAnalytics do
  @moduledoc """
  Project-level spend aggregation from Budget.Usage records.
  """

  import Ecto.Query

  alias HydraX.Budget.Usage
  alias HydraX.Product.Pricing
  alias HydraX.Repo

  def project_summary(project_id) do
    agent_pairs = project_agent_ids(project_id)
    now = DateTime.utc_now()
    month_start = beginning_of_month()
    week_start = DateTime.add(now, -7 * 86400)
    day_start = beginning_of_day()
    yesterday_start = DateTime.add(day_start, -86400)

    month = aggregate_period(agent_pairs, month_start, now)
    week = aggregate_period(agent_pairs, week_start, now)
    today = aggregate_period(agent_pairs, day_start, now)
    yesterday = aggregate_period(agent_pairs, yesterday_start, day_start)

    budget = get_project_budget(project_id)

    %{
      month_tokens: month.tokens,
      month_cost_cents: month.cost_cents,
      week_tokens: week.tokens,
      week_cost_cents: week.cost_cents,
      today_tokens: today.tokens,
      today_cost_cents: today.cost_cents,
      yesterday_tokens: yesterday.tokens,
      yesterday_cost_cents: yesterday.cost_cents,
      budget_cents: budget,
      budget_percent:
        if(budget && budget > 0,
          do: min(round(month.cost_cents / budget * 100), 100),
          else: nil
        )
    }
  end

  def spend_by_agent(project_id, period_start, period_end) do
    project_agent_ids(project_id)
    |> Enum.map(fn {persona, agent_id} ->
      usages = agent_usage_in_period(agent_id, period_start, period_end)

      tokens = Enum.reduce(usages, 0, fn u, acc -> acc + u.tokens_in + u.tokens_out end)

      cost_cents =
        Enum.reduce(usages, 0, fn u, acc ->
          model = get_in(u.metadata || %{}, ["model"]) || "default"
          acc + Pricing.cost_cents(model, u.tokens_in, u.tokens_out)
        end)

      by_model =
        usages
        |> Enum.group_by(fn u -> get_in(u.metadata || %{}, ["model"]) || "unknown" end)
        |> Enum.map(fn {model, model_usages} ->
          m_in = Enum.reduce(model_usages, 0, fn u, acc -> acc + u.tokens_in end)
          m_out = Enum.reduce(model_usages, 0, fn u, acc -> acc + u.tokens_out end)
          %{model: model, tokens_in: m_in, tokens_out: m_out, cost_cents: Pricing.cost_cents(model, m_in, m_out)}
        end)
        |> Enum.sort_by(& &1.cost_cents, :desc)

      %{persona: persona, tokens: tokens, cost_cents: cost_cents, by_model: by_model}
    end)
    |> Enum.sort_by(& &1.cost_cents, :desc)
  end

  def spend_by_model(project_id, period_start, period_end) do
    agent_ids = project_agent_ids(project_id) |> Enum.map(fn {_, id} -> id end)

    Usage
    |> where([u], u.agent_id in ^agent_ids and u.inserted_at >= ^period_start and u.inserted_at <= ^period_end)
    |> Repo.all()
    |> Enum.group_by(fn u -> get_in(u.metadata || %{}, ["model"]) || "unknown" end)
    |> Enum.map(fn {model, usages} ->
      t_in = Enum.reduce(usages, 0, fn u, acc -> acc + u.tokens_in end)
      t_out = Enum.reduce(usages, 0, fn u, acc -> acc + u.tokens_out end)
      %{model: model, tokens_in: t_in, tokens_out: t_out, cost_cents: Pricing.cost_cents(model, t_in, t_out)}
    end)
    |> Enum.sort_by(& &1.cost_cents, :desc)
  end

  def daily_spend(project_id, days \\ 30) do
    agent_ids = project_agent_ids(project_id) |> Enum.map(fn {_, id} -> id end)
    since = DateTime.add(DateTime.utc_now(), -days * 86400)

    Usage
    |> where([u], u.agent_id in ^agent_ids and u.inserted_at >= ^since)
    |> Repo.all()
    |> Enum.group_by(fn u -> Date.to_iso8601(DateTime.to_date(u.inserted_at)) end)
    |> Enum.map(fn {date, usages} ->
      tokens = Enum.reduce(usages, 0, fn u, acc -> acc + u.tokens_in + u.tokens_out end)

      cost =
        Enum.reduce(usages, 0, fn u, acc ->
          model = get_in(u.metadata || %{}, ["model"]) || "default"
          acc + Pricing.cost_cents(model, u.tokens_in, u.tokens_out)
        end)

      %{date: date, tokens: tokens, cost_cents: cost}
    end)
    |> Enum.sort_by(& &1.date)
  end

  def recent_log(project_id, limit \\ 25, offset \\ 0) do
    agent_pairs = project_agent_ids(project_id)
    agent_ids = Enum.map(agent_pairs, fn {_, id} -> id end)
    agent_map = Map.new(agent_pairs, fn {persona, id} -> {id, persona} end)

    base_query = Usage |> where([u], u.agent_id in ^agent_ids)

    total = base_query |> Repo.aggregate(:count, :id)

    entries =
      base_query
      |> order_by([u], desc: u.inserted_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(fn u ->
        model = get_in(u.metadata || %{}, ["model"]) || "unknown"

        %{
          id: u.id,
          agent: Map.get(agent_map, u.agent_id, "unknown"),
          model: model,
          tokens_in: u.tokens_in,
          tokens_out: u.tokens_out,
          cost_cents: Pricing.cost_cents(model, u.tokens_in, u.tokens_out),
          inserted_at: u.inserted_at
        }
      end)

    {entries, total}
  end

  # --- Helpers ---

  defp aggregate_period(agent_id_pairs, period_start, period_end) do
    agent_ids = Enum.map(agent_id_pairs, fn {_, id} -> id end)

    usages =
      Usage
      |> where([u], u.agent_id in ^agent_ids and u.inserted_at >= ^period_start and u.inserted_at <= ^period_end)
      |> Repo.all()

    tokens = Enum.reduce(usages, 0, fn u, acc -> acc + u.tokens_in + u.tokens_out end)

    cost =
      Enum.reduce(usages, 0, fn u, acc ->
        model = get_in(u.metadata || %{}, ["model"]) || "default"
        acc + Pricing.cost_cents(model, u.tokens_in, u.tokens_out)
      end)

    %{tokens: tokens, cost_cents: cost}
  end

  defp project_agent_ids(project_id) do
    project = HydraX.Product.get_project!(project_id)

    [
      {"researcher", project.researcher_agent_id},
      {"strategist", project.strategist_agent_id},
      {"architect", project.architect_agent_id},
      {"designer", project.designer_agent_id},
      {"memory_agent", project.memory_agent_id}
    ]
    |> Enum.reject(fn {_, id} -> is_nil(id) end)
  end

  defp agent_usage_in_period(agent_id, period_start, period_end) do
    Usage
    |> where([u], u.agent_id == ^agent_id and u.inserted_at >= ^period_start and u.inserted_at <= ^period_end)
    |> Repo.all()
  end

  defp get_project_budget(project_id) do
    project = HydraX.Product.get_project!(project_id)
    get_in(project.metadata || %{}, ["budget_cents"])
  end

  defp beginning_of_month do
    today = Date.utc_today()
    {:ok, dt} = NaiveDateTime.new(today.year, today.month, 1, 0, 0, 0)
    DateTime.from_naive!(dt, "Etc/UTC")
  end

  defp beginning_of_day do
    {:ok, dt} = NaiveDateTime.new(Date.utc_today(), ~T[00:00:00])
    DateTime.from_naive!(dt, "Etc/UTC")
  end
end
