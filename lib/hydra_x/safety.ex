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
end
