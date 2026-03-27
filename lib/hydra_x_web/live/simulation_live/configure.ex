defmodule HydraXWeb.SimulationLive.Configure do
  use HydraXWeb, :live_view

  alias HydraX.Simulation.Config
  alias HydraX.Simulation.Agent.Persona

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Simulation")
     |> assign(:current, "simulations")
     |> assign(:step, 1)
     |> assign(:config, %Config{})
     |> assign(:seed_material, "")
     |> assign(:archetypes, Persona.archetypes())
     |> assign(:distribution, %{
       cautious_cfo: 5,
       visionary_ceo: 3,
       pragmatic_ops_director: 7,
       aggressive_competitor: 5
     })}
  end

  @impl true
  def handle_event("update_config", params, socket) do
    config = %Config{
      name: params["name"] || socket.assigns.config.name,
      max_ticks: parse_int(params["max_ticks"], 40),
      tick_interval_ms: parse_int(params["tick_interval_ms"], 500),
      max_budget_cents: parse_int(params["max_budget_cents"], 50),
      event_frequency: parse_float(params["event_frequency"], 0.3),
      crisis_probability: parse_float(params["crisis_probability"], 0.05),
      market_volatility: parse_float(params["market_volatility"], 0.5)
    }

    {:noreply, assign(socket, :config, config)}
  end

  def handle_event("update_seed", %{"seed" => seed}, socket) do
    {:noreply, assign(socket, :seed_material, seed)}
  end

  def handle_event("next_step", _params, socket) do
    {:noreply, assign(socket, :step, min(socket.assigns.step + 1, 4))}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, :step, max(socket.assigns.step - 1, 1))}
  end

  def handle_event("create_simulation", _params, socket) do
    config = socket.assigns.config

    attrs = %{
      name: config.name,
      status: "configuring",
      config: Map.from_struct(config),
      seed_material: socket.assigns.seed_material
    }

    case HydraX.Repo.insert(
           HydraX.Simulation.Schema.Simulation.changeset(
             %HydraX.Simulation.Schema.Simulation{},
             attrs
           )
         ) do
      {:ok, sim} ->
        {:noreply, push_navigate(socket, to: ~p"/simulations/#{sim.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create simulation")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto space-y-6">
      <h1 class="text-xl font-semibold text-zinc-100">Configure Simulation</h1>

      <div class="flex gap-2 mb-6">
        <%= for {label, step_num} <- [{"Setup", 1}, {"Agents", 2}, {"World", 3}, {"Review", 4}] do %>
          <div class={"flex-1 h-1 rounded #{if step_num <= @step, do: "bg-blue-500", else: "bg-zinc-700"}"} />
        <% end %>
      </div>

      <%= case @step do %>
        <% 1 -> %>
          <div class="space-y-4">
            <div>
              <label class="block text-sm text-zinc-300 mb-1">Simulation Name</label>
              <input
                type="text"
                value={@config.name}
                phx-blur="update_config"
                name="name"
                class="w-full rounded-lg bg-zinc-800 border-zinc-600 text-zinc-100 px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm text-zinc-300 mb-1">Seed Material</label>
              <textarea
                phx-blur="update_seed"
                name="seed"
                rows="8"
                placeholder="Paste company report, market analysis, or scenario description..."
                class="w-full rounded-lg bg-zinc-800 border-zinc-600 text-zinc-100 px-3 py-2"
              ><%= @seed_material %></textarea>
            </div>
          </div>
        <% 2 -> %>
          <div class="space-y-4">
            <h3 class="text-sm font-medium text-zinc-300">Agent Population</h3>
            <%= for archetype <- @archetypes do %>
              <div class="flex items-center justify-between">
                <span class="text-sm text-zinc-300">{archetype}</span>
                <span class="text-sm text-zinc-400">
                  {Map.get(@distribution, archetype, 0)} agents
                </span>
              </div>
            <% end %>
          </div>
        <% 3 -> %>
          <div class="space-y-4">
            <h3 class="text-sm font-medium text-zinc-300">World Parameters</h3>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs text-zinc-400">Max Ticks</label>
                <input
                  type="number"
                  value={@config.max_ticks}
                  name="max_ticks"
                  phx-blur="update_config"
                  class="w-full rounded bg-zinc-800 border-zinc-600 text-zinc-100 px-2 py-1 text-sm"
                />
              </div>
              <div>
                <label class="block text-xs text-zinc-400">Budget (cents)</label>
                <input
                  type="number"
                  value={@config.max_budget_cents}
                  name="max_budget_cents"
                  phx-blur="update_config"
                  class="w-full rounded bg-zinc-800 border-zinc-600 text-zinc-100 px-2 py-1 text-sm"
                />
              </div>
              <div>
                <label class="block text-xs text-zinc-400">Event Frequency</label>
                <input
                  type="number"
                  step="0.1"
                  value={@config.event_frequency}
                  name="event_frequency"
                  phx-blur="update_config"
                  class="w-full rounded bg-zinc-800 border-zinc-600 text-zinc-100 px-2 py-1 text-sm"
                />
              </div>
              <div>
                <label class="block text-xs text-zinc-400">Market Volatility</label>
                <input
                  type="number"
                  step="0.1"
                  value={@config.market_volatility}
                  name="market_volatility"
                  phx-blur="update_config"
                  class="w-full rounded bg-zinc-800 border-zinc-600 text-zinc-100 px-2 py-1 text-sm"
                />
              </div>
            </div>
          </div>
        <% 4 -> %>
          <div class="space-y-4">
            <h3 class="text-sm font-medium text-zinc-300">Review</h3>
            <dl class="space-y-2 text-sm">
              <div class="flex justify-between">
                <dt class="text-zinc-400">Name</dt>
                <dd class="text-zinc-100">{@config.name}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Ticks</dt>
                <dd class="text-zinc-100">{@config.max_ticks}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-400">Budget</dt>
                <dd class="text-zinc-100">${@config.max_budget_cents / 100}</dd>
              </div>
            </dl>
            <button
              phx-click="create_simulation"
              class="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500"
            >
              Create Simulation
            </button>
          </div>
      <% end %>

      <div class="flex justify-between pt-4">
        <button
          :if={@step > 1}
          phx-click="prev_step"
          class="text-sm text-zinc-400 hover:text-zinc-200"
        >
          Back
        </button>
        <div :if={@step > 1} />
        <button
          :if={@step < 4}
          phx-click="next_step"
          class="rounded-lg bg-zinc-700 px-4 py-2 text-sm text-zinc-200 hover:bg-zinc-600"
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_float(nil, default), do: default

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_float(val, _default) when is_float(val), do: val
end
