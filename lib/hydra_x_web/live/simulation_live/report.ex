defmodule HydraXWeb.SimulationLive.Report do
  use HydraXWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    simulation = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)

    reports =
      import Ecto.Query

    HydraX.Repo.all(
      from r in HydraX.Simulation.Schema.SimReport,
        where: r.simulation_id == ^id,
        order_by: [desc: r.generated_at]
    )

    {:ok,
     socket
     |> assign(:page_title, "#{simulation.name} — Report")
     |> assign(:current, "simulations")
     |> assign(:simulation, simulation)
     |> assign(:reports, reports)
     |> assign(:generating, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <.link
            navigate={~p"/simulations/#{@simulation.id}"}
            class="text-sm text-zinc-400 hover:text-zinc-200"
          >
            &larr; Back to simulation
          </.link>
          <h1 class="text-xl font-semibold text-zinc-100 mt-1">{@simulation.name} — Reports</h1>
        </div>
      </div>

      <%= if @reports == [] do %>
        <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-8 text-center">
          <p class="text-zinc-400">No reports generated yet.</p>
          <p class="text-sm text-zinc-500 mt-1">Reports are generated after simulation completes.</p>
        </div>
      <% else %>
        <%= for report <- @reports do %>
          <div class="rounded-lg border border-zinc-700 bg-zinc-800/50 p-6">
            <div class="text-xs text-zinc-500 mb-4">
              Generated: {report.generated_at}
            </div>
            <div class="prose prose-invert prose-sm max-w-none">
              {Phoenix.HTML.raw(render_markdown(report.content))}
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_markdown(nil), do: ""

  defp render_markdown(content) do
    content
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\n\n/, "</p><p>")
    |> then(&"<p>#{&1}</p>")
  end
end
