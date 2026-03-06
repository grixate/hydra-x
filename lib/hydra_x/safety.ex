defmodule HydraX.Safety do
  @moduledoc """
  Append-only safety event logging.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Safety.Event

  def log_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def recent_events(agent_id, limit \\ 20) do
    Event
    |> where([event], event.agent_id == ^agent_id)
    |> order_by([event], desc: event.inserted_at)
    |> limit(^limit)
    |> preload([:conversation])
    |> Repo.all()
  end

  def recent_events_global(limit \\ 20) do
    list_events(limit: limit)
  end

  def list_events(opts \\ []) do
    level = Keyword.get(opts, :level)
    category = Keyword.get(opts, :category)
    agent_id = Keyword.get(opts, :agent_id)
    limit = Keyword.get(opts, :limit, 20)

    Event
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_level(level)
    |> maybe_filter_category(category)
    |> order_by([event], desc: event.inserted_at)
    |> limit(^limit)
    |> preload([:conversation, :agent])
    |> Repo.all()
  end

  def categories(limit \\ 100) do
    list_events(limit: limit)
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def recent_counts(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back * 3600, :second)

    Event
    |> where([event], event.inserted_at >= ^cutoff)
    |> group_by([event], event.level)
    |> select([event], {event.level, count(event.id)})
    |> Repo.all()
    |> Enum.into(%{}, fn {level, count} -> {level, count} end)
  end

  defp maybe_filter_agent(query, nil), do: query
  defp maybe_filter_agent(query, agent_id), do: where(query, [event], event.agent_id == ^agent_id)

  defp maybe_filter_level(query, nil), do: query
  defp maybe_filter_level(query, ""), do: query
  defp maybe_filter_level(query, level), do: where(query, [event], event.level == ^level)

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, ""), do: query

  defp maybe_filter_category(query, category),
    do: where(query, [event], event.category == ^category)
end
