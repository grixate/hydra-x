defmodule HydraXWeb.SimulationChannel do
  use HydraXWeb, :channel

  alias HydraX.Simulation.World.EventBus
  alias HydraXWeb.ProductChannelAuth

  @impl true
  def join("simulation:" <> raw_id, _params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         :ok <- ProductChannelAuth.allow_sandbox(socket),
         {sim_id, ""} <- Integer.parse(raw_id) do
      # Subscribe to simulation event bus
      Phoenix.PubSub.subscribe(HydraX.PubSub, EventBus.topic(sim_id))

      {:ok, %{sim_id: sim_id},
       socket
       |> assign(:sim_id, sim_id)}
    else
      :error -> {:error, %{reason: "invalid_id"}}
      {_, _} -> {:error, %{reason: "invalid_id"}}
    end
  end

  @impl true
  def handle_info({:tick_complete, tick_data}, socket) do
    push(socket, "tick_complete", %{
      tick: tick_data.tick_number,
      event_count: Map.get(tick_data, :event_count, 0),
      action_count: Map.get(tick_data, :action_count, 0),
      llm_calls: Map.get(tick_data, :llm_calls, 0),
      cost_cents: Map.get(tick_data, :cost_cents, 0),
      duration_us: Map.get(tick_data, :duration_us, 0),
      tier_counts: Map.get(tick_data, :tier_counts, %{}),
      agent_states: Map.get(tick_data, :agent_states, []),
      events: format_events(Map.get(tick_data, :events, []))
    })

    {:noreply, socket}
  end

  def handle_info({:simulation_lifecycle, event}, socket) do
    push(socket, "lifecycle", %{event: to_string(event)})
    {:noreply, socket}
  end

  def handle_info({:world_events, events}, socket) do
    push(socket, "world_events", %{events: format_events(events)})
    {:noreply, socket}
  end

  def handle_info({:agent_action, agent_id, action}, socket) do
    push(socket, "agent_action", %{
      agent_id: agent_id,
      action_type: to_string(Map.get(action, :type, "unknown")),
      method: to_string(Map.get(action, :method, "unknown"))
    })

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp format_events(events) do
    Enum.map(events, fn event ->
      %{
        id: Map.get(event, :id),
        type: to_string(Map.get(event, :type)),
        source: Map.get(event, :source),
        target: Map.get(event, :target),
        description: Map.get(event, :description),
        stakes: Map.get(event, :stakes, 0),
        tick: Map.get(event, :tick)
      }
    end)
  end
end
