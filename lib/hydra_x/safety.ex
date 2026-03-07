defmodule HydraX.Safety do
  @moduledoc """
  Append-only safety event logging.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Safety.Event

  def log_event(attrs) do
    attrs = Map.put_new(attrs, :status, "open")

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
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 20)

    Event
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_level(level)
    |> maybe_filter_category(category)
    |> maybe_filter_status(status)
    |> order_by([event], desc: event.inserted_at)
    |> limit(^limit)
    |> preload([:conversation, :agent])
    |> Repo.all()
  end

  def get_event!(id), do: Repo.get!(Event, id) |> Repo.preload([:conversation, :agent])

  def acknowledge_event!(id, actor, note \\ nil) do
    update_event_status!(id, "acknowledged", actor, note)
  end

  def resolve_event!(id, actor, note \\ nil) do
    update_event_status!(id, "resolved", actor, note)
  end

  def reopen_event!(id, actor, note \\ nil) do
    update_event_status!(id, "open", actor, note)
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

  def status_counts(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back * 3600, :second)

    Event
    |> where([event], event.inserted_at >= ^cutoff)
    |> group_by([event], event.status)
    |> select([event], {event.status, count(event.id)})
    |> Repo.all()
    |> Enum.into(%{}, fn {status, count} -> {status, count} end)
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

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [event], event.status == ^status)

  defp update_event_status!(id, status, actor, note) do
    event = get_event!(id)
    now = DateTime.utc_now()

    attrs =
      case status do
        "acknowledged" ->
          %{
            status: status,
            acknowledged_at: now,
            acknowledged_by: actor,
            operator_note: note || event.operator_note
          }

        "resolved" ->
          %{
            status: status,
            acknowledged_at: event.acknowledged_at || now,
            acknowledged_by: event.acknowledged_by || actor,
            resolved_at: now,
            resolved_by: actor,
            operator_note: note || event.operator_note
          }

        "open" ->
          %{
            status: status,
            acknowledged_at: nil,
            acknowledged_by: nil,
            resolved_at: nil,
            resolved_by: nil,
            operator_note: note || event.operator_note
          }
      end

    event
    |> Event.changeset(attrs)
    |> Repo.update!()
    |> Repo.preload([:conversation, :agent])
  end
end
