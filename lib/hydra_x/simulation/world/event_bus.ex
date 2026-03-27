defmodule HydraX.Simulation.World.EventBus do
  @moduledoc """
  PubSub wrapper for simulation event broadcast.

  All simulation events flow through HydraX.PubSub under the topic
  `"simulation:<sim_id>"`. This module provides a typed broadcast interface
  and subscription helpers.
  """

  @doc "Subscribe to all events for a simulation."
  def subscribe(sim_id) do
    Phoenix.PubSub.subscribe(HydraX.PubSub, topic(sim_id))
  end

  @doc "Unsubscribe from simulation events."
  def unsubscribe(sim_id) do
    Phoenix.PubSub.unsubscribe(HydraX.PubSub, topic(sim_id))
  end

  @doc "Broadcast that a tick has completed with summary data."
  def broadcast_tick_complete(sim_id, tick_data) do
    Phoenix.PubSub.broadcast(HydraX.PubSub, topic(sim_id), {:tick_complete, tick_data})
  end

  @doc "Broadcast a simulation lifecycle event."
  def broadcast_lifecycle(sim_id, event)
      when event in [:started, :paused, :resumed, :completed, :failed] do
    Phoenix.PubSub.broadcast(HydraX.PubSub, topic(sim_id), {:simulation_lifecycle, event})
  end

  @doc "Broadcast world events to all subscribers."
  def broadcast_world_events(sim_id, events) do
    Phoenix.PubSub.broadcast(HydraX.PubSub, topic(sim_id), {:world_events, events})
  end

  @doc "Broadcast an agent action."
  def broadcast_agent_action(sim_id, agent_id, action) do
    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      topic(sim_id),
      {:agent_action, agent_id, action}
    )
  end

  defp topic(sim_id), do: "simulation:#{sim_id}"
end
