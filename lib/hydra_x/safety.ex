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
    Event
    |> order_by([event], desc: event.inserted_at)
    |> limit(^limit)
    |> preload([:conversation, :agent])
    |> Repo.all()
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
end
