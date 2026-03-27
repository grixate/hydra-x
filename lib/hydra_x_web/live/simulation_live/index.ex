defmodule HydraXWeb.SimulationLive.Index do
  use HydraXWeb, :live_view

  alias HydraX.Simulation.Schema

  @impl true
  def mount(_params, _session, socket) do
    simulations = list_simulations()

    {:ok,
     socket
     |> assign(:page_title, "Simulations")
     |> assign(:current, "simulations")
     |> assign(:simulations, simulations)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/simulations/new")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold text-zinc-100">Simulations</h1>
          <p class="text-sm text-zinc-400 mt-1">Multi-agent strategy simulation engine</p>
        </div>
        <button
          phx-click="create"
          class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500"
        >
          New Simulation
        </button>
      </div>

      <div class="grid gap-4">
        <%= if @simulations == [] do %>
          <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-8 text-center">
            <p class="text-zinc-400">No simulations yet. Create one to get started.</p>
          </div>
        <% else %>
          <%= for sim <- @simulations do %>
            <.link
              navigate={~p"/simulations/#{sim.id}"}
              class="block rounded-lg border border-zinc-700 bg-zinc-800/50 p-4 hover:border-zinc-500 transition"
            >
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="font-medium text-zinc-100">{sim.name}</h3>
                  <p class="text-sm text-zinc-400 mt-1">
                    {sim.total_ticks} ticks · ${(sim.total_cost_cents || 0) / 100}
                  </p>
                </div>
                <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(sim.status)}"}>
                  {sim.status}
                </span>
              </div>
            </.link>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp list_simulations do
    import Ecto.Query
    HydraX.Repo.all(from s in Schema.Simulation, order_by: [desc: s.inserted_at])
  rescue
    _ -> []
  end

  defp status_color("completed"), do: "bg-green-900/50 text-green-400"
  defp status_color("running"), do: "bg-blue-900/50 text-blue-400"
  defp status_color("paused"), do: "bg-yellow-900/50 text-yellow-400"
  defp status_color("failed"), do: "bg-red-900/50 text-red-400"
  defp status_color(_), do: "bg-zinc-700 text-zinc-300"
end
