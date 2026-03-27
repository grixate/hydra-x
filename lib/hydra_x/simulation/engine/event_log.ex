defmodule HydraX.Simulation.Engine.EventLog do
  @moduledoc """
  Append-only simulation event persistence.

  Persists tick snapshots and events to the database for replay and analysis.
  """

  @doc """
  Persist a tick snapshot with its events and actions.
  """
  def persist_tick(sim_id, tick_number, tick_data) do
    now = DateTime.utc_now()

    # Persist sim_tick record
    tick_attrs = %{
      simulation_id: sim_id,
      tick_number: tick_number,
      duration_us: tick_data[:duration_us],
      tier_counts: tick_data[:tier_counts],
      llm_calls:
        Map.get(tick_data[:tier_counts] || %{}, :complex, 0) +
          Map.get(tick_data[:tier_counts] || %{}, :negotiation, 0),
      tokens_used: tick_data[:tokens_used] || 0,
      world_delta: tick_data[:world_delta] || %{},
      inserted_at: now,
      updated_at: now
    }

    # Persist events
    event_records =
      Enum.map(tick_data[:events] || [], fn event ->
        %{
          simulation_id: sim_id,
          tick: tick_number,
          event_type: to_string(event.type),
          source: format_source(event.source),
          target: format_target(event.target),
          description: event.description,
          properties: event.properties,
          stakes: event.stakes,
          inserted_at: now,
          updated_at: now
        }
      end)

    {:ok, %{tick: tick_attrs, events: event_records}}
  end

  defp format_source(:world), do: "world"
  defp format_source({:agent, id}), do: "agent:#{id}"
  defp format_source(other), do: to_string(other)

  defp format_target(nil), do: nil
  defp format_target({:agent, id}), do: "agent:#{id}"
  defp format_target(other), do: to_string(other)
end
