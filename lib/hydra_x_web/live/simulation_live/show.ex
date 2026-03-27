defmodule HydraXWeb.SimulationLive.Show do
  use HydraXWeb, :live_view

  alias HydraX.Simulation.World.EventBus

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    simulation = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)

    if connected?(socket) do
      EventBus.subscribe(to_string(id))
    end

    {:ok,
     socket
     |> assign(:page_title, simulation.name)
     |> assign(:current, "simulations")
     |> assign(:simulation, simulation)
     |> assign(:tick, simulation.total_ticks)
     |> assign(:total_cost, simulation.total_cost_cents || 0)
     |> assign(:tier_counts, %{routine: 0, emotional: 0, complex: 0, negotiation: 0})
     |> assign(:events, [])
     |> assign(:selected_agent, nil)}
  end

  @impl true
  def handle_info({:tick_complete, tick_data}, socket) do
    events =
      (tick_data.notable_events ++ socket.assigns.events)
      |> Enum.take(50)

    socket =
      socket
      |> assign(:tick, tick_data.tick_number)
      |> assign(:tier_counts, tick_data.tier_counts)
      |> assign(:total_cost, socket.assigns.total_cost + (tick_data[:cost_cents] || 0))
      |> assign(:events, events)
      |> push_event("tick_update", %{
        tick: tick_data.tick_number,
        node_updates: tick_data[:agent_state_changes] || [],
        edge_updates: tick_data[:relationship_changes] || [],
        new_edges: tick_data[:new_relationships] || [],
        removed_edges: tick_data[:removed_relationships] || [],
        events: Enum.take(tick_data[:notable_events] || [], 3),
        tier_counts: tick_data.tier_counts,
        cost_cents: tick_data[:cost_cents] || 0
      })

    {:noreply, socket}
  end

  def handle_info({:simulation_lifecycle, _event}, socket) do
    simulation =
      HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, socket.assigns.simulation.id)

    {:noreply, assign(socket, :simulation, simulation)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_agent", %{"id" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent, agent_id)}
  end

  def handle_event("deselect_agent", _params, socket) do
    {:noreply, assign(socket, :selected_agent, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-semibold text-zinc-100">{@simulation.name}</h1>
          <p class="text-sm text-zinc-400">
            Tick {@tick} / {(@simulation.config || %{})["max_ticks"] || "?"}
          </p>
        </div>
        <span class={"px-3 py-1 rounded text-sm font-medium #{status_color(@simulation.status)}"}>
          {@simulation.status}
        </span>
      </div>

      <div class="grid grid-cols-4 gap-3">
        <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-3 text-center">
          <div class="text-2xl font-bold text-zinc-100">{@tier_counts[:routine] || 0}</div>
          <div class="text-xs text-zinc-400">Routine</div>
        </div>
        <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-3 text-center">
          <div class="text-2xl font-bold text-purple-400">{@tier_counts[:complex] || 0}</div>
          <div class="text-xs text-zinc-400">Complex (LLM)</div>
        </div>
        <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-3 text-center">
          <div class="text-2xl font-bold text-blue-400">{@tier_counts[:negotiation] || 0}</div>
          <div class="text-xs text-zinc-400">Negotiation</div>
        </div>
        <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-3 text-center">
          <div class="text-2xl font-bold text-green-400">${@total_cost / 100}</div>
          <div class="text-xs text-zinc-400">Cost</div>
        </div>
      </div>

      <%!-- D3 Graph Container --%>
      <div
        id="sim-graph"
        phx-hook="SimGraphHook"
        data-initial-nodes="[]"
        data-initial-links="[]"
        class="rounded-lg border border-zinc-700 bg-zinc-900 min-h-[400px]"
      >
      </div>

      <%!-- Event Feed --%>
      <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-4">
        <h3 class="text-sm font-medium text-zinc-300 mb-2">Event Feed</h3>
        <div class="space-y-1 max-h-48 overflow-y-auto">
          <%= for event <- @events do %>
            <div class="text-xs text-zinc-400 flex items-center gap-2">
              <span class={"w-2 h-2 rounded-full #{event_dot_color(event)}"} />
              <span>{Map.get(event, :description, Map.get(event, :type, ""))}</span>
              <span class="text-zinc-600 ml-auto">
                stakes: {Map.get(event, :stakes, 0)}
              </span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp status_color("completed"), do: "bg-green-900/50 text-green-400"
  defp status_color("running"), do: "bg-blue-900/50 text-blue-400"
  defp status_color("paused"), do: "bg-yellow-900/50 text-yellow-400"
  defp status_color("failed"), do: "bg-red-900/50 text-red-400"
  defp status_color(_), do: "bg-zinc-700 text-zinc-300"

  defp event_dot_color(event) do
    cond do
      Map.get(event, :is_crisis?, false) -> "bg-red-500"
      Map.get(event, :is_opportunity?, false) -> "bg-green-500"
      true -> "bg-zinc-500"
    end
  end
end
