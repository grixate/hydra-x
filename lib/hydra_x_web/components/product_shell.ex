defmodule HydraXWeb.ProductShell do
  use HydraXWeb, :html

  attr :current, :string, required: true
  attr :project, :map, required: true
  attr :board_sessions, :list, default: []
  attr :agents, :list, default: []
  attr :my_work_counts, :map, default: %{needs_input: 0}
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-[var(--hx-bg)] text-[var(--hx-ink)]">
      <div class="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top_left,rgba(245,110,66,0.18),transparent_34%),radial-gradient(circle_at_bottom_right,rgba(36,56,68,0.16),transparent_35%)]">
      </div>
      <div class="relative mx-auto flex min-h-screen max-w-7xl flex-col gap-8 px-4 py-6 sm:px-6 lg:flex-row lg:px-8">
        <aside class="glass-panel w-full shrink-0 overflow-hidden lg:sticky lg:top-6 lg:w-80 lg:self-start">
          <%!-- Project header --%>
          <div class="border-b border-white/10 px-5 py-5">
            <div class="text-xs uppercase tracking-[0.35em] text-[var(--hx-mute)]">Product Graph</div>
            <div class="mt-3 flex items-end justify-between gap-4">
              <div>
                <h1 class="font-display text-2xl leading-none">{@project.name}</h1>
                <p :if={@project.description} class="mt-2 max-w-xs text-sm text-[var(--hx-mute)]">
                  {String.slice(@project.description || "", 0..80)}
                </p>
              </div>
            </div>
          </div>

          <%!-- Navigation --%>
          <nav class="grid gap-2 px-3 py-3">
            <.product_nav_link
              current={@current}
              value="stream"
              href={~p"/projects/#{@project.id}/stream"}
              label="Stream"
              badge={@my_work_counts.needs_input}
            />
            <.product_nav_link
              current={@current}
              value="graph"
              href={~p"/projects/#{@project.id}/graph"}
              label="Graph"
            />
            <.product_nav_link
              current={@current}
              value="board"
              href={~p"/projects/#{@project.id}/board"}
              label="Board"
            />

            <%!-- Board sessions sub-items --%>
            <div :if={@current in ["board", "board_show"]} class="ml-6 grid gap-1">
              <.link
                :for={session <- @board_sessions}
                navigate={~p"/projects/#{@project.id}/board/#{session.id}"}
                class="flex items-center justify-between rounded-xl px-3 py-2 text-xs text-[var(--hx-mute)] hover:bg-white/5 hover:text-white transition"
              >
                <span class="truncate">{session.title}</span>
                <span :if={session.status == "active"} class="ml-2 text-[10px] text-[var(--hx-accent)]">active</span>
              </.link>
              <.link
                navigate={~p"/projects/#{@project.id}/board?new=1"}
                class="flex items-center gap-1 rounded-xl px-3 py-2 text-xs text-[var(--hx-mute)] hover:bg-white/5 hover:text-white transition"
              >
                <span>+ New session</span>
              </.link>
            </div>

            <.product_nav_link
              current={@current}
              value="simulation"
              href={~p"/simulations"}
              label="Simulation"
            />
          </nav>

          <%!-- Agents section --%>
          <div class="border-t border-white/10 px-5 py-4">
            <div class="mb-3 text-[10px] uppercase tracking-[0.25em] text-[var(--hx-mute)]">Agents</div>
            <div class="grid gap-2">
              <div
                :for={agent <- @agents}
                class="flex items-center justify-between rounded-xl px-3 py-2 text-xs transition hover:bg-white/5 cursor-pointer"
              >
                <span class="text-white/80">{agent_display_name(agent)}</span>
                <span class={[
                  "text-[10px] uppercase tracking-wider",
                  agent_status_color(agent)
                ]}>{agent_status_label(agent)}</span>
              </div>
            </div>
          </div>

          <%!-- Settings link --%>
          <div class="border-t border-white/10 px-5 py-4">
            <.link
              navigate={~p"/"}
              class="text-xs text-[var(--hx-mute)] hover:text-white transition"
            >
              Operator Lattice
            </.link>
          </div>
        </aside>

        <main class="flex-1">
          <Layouts.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr :current, :string, required: true
  attr :value, :string, required: true
  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :badge, :integer, default: 0

  defp product_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "group flex items-center justify-between rounded-2xl border px-4 py-3 transition",
        if(@current == @value,
          do:
            "border-[var(--hx-accent)] bg-[rgba(245,110,66,0.12)] text-white shadow-[0_0_0_1px_rgba(245,110,66,0.15)]",
          else:
            "border-transparent bg-transparent text-[var(--hx-mute)] hover:border-white/10 hover:bg-white/5 hover:text-white"
        )
      ]}
    >
      <span class="font-mono text-xs uppercase tracking-[0.18em]">{@label}</span>
      <span :if={@badge > 0} class="rounded-full bg-[var(--hx-accent)] px-2 py-0.5 text-[10px] font-bold text-white">
        {@badge}
      </span>
    </.link>
    """
  end

  defp agent_display_name(%{name: name}), do: name
  defp agent_display_name(%{slug: slug}), do: String.capitalize(slug)
  defp agent_display_name(_), do: "Agent"

  defp agent_status_label(%{status: "active"}), do: "active"
  defp agent_status_label(_), do: "idle"

  defp agent_status_color(%{status: "active"}), do: "text-green-400"
  defp agent_status_color(_), do: "text-[var(--hx-mute)]"
end
