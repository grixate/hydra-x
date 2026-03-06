defmodule HydraXWeb.AppShell do
  use HydraXWeb, :html

  attr :current, :string, required: true
  attr :stats, :map, default: %{}
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-[var(--hx-bg)] text-[var(--hx-ink)]">
      <div class="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top_left,rgba(245,110,66,0.18),transparent_34%),radial-gradient(circle_at_bottom_right,rgba(36,56,68,0.16),transparent_35%)]">
      </div>
      <div class="relative mx-auto flex min-h-screen max-w-7xl flex-col gap-8 px-4 py-6 sm:px-6 lg:flex-row lg:px-8">
        <aside class="glass-panel w-full shrink-0 overflow-hidden lg:sticky lg:top-6 lg:w-80 lg:self-start">
          <div class="border-b border-white/10 px-5 py-5">
            <div class="text-xs uppercase tracking-[0.35em] text-[var(--hx-mute)]">Hydra-X</div>
            <div class="mt-3 flex items-end justify-between gap-4">
              <div>
                <h1 class="font-display text-3xl leading-none">Operator lattice</h1>
                <p class="mt-2 max-w-xs text-sm text-[var(--hx-mute)]">
                  Runtime, memory, and channels wired into a single control surface.
                </p>
              </div>
              <div class="grid h-14 w-14 place-items-center rounded-2xl border border-white/10 bg-[rgba(255,255,255,0.04)] font-mono text-sm">
                HX
              </div>
            </div>
          </div>

          <nav class="grid gap-2 px-3 py-3">
            <.nav_link current={@current} value="home" href={~p"/"} label="Overview" />
            <.nav_link current={@current} value="setup" href={~p"/setup"} label="Setup" />
            <.nav_link current={@current} value="agents" href={~p"/agents"} label="Agents" />
            <.nav_link
              current={@current}
              value="conversations"
              href={~p"/conversations"}
              label="Conversations"
            />
            <.nav_link current={@current} value="memory" href={~p"/memory"} label="Memory" />
            <.nav_link
              current={@current}
              value="providers"
              href={~p"/settings/providers"}
              label="Providers"
            />
            <.nav_link current={@current} value="health" href={~p"/health"} label="Health" />
          </nav>

          <div class="grid grid-cols-2 gap-3 border-t border-white/10 px-5 py-5">
            <div>
              <div class="text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">Agents</div>
              <div class="mt-1 font-display text-3xl">{Map.get(@stats, :agents, 0)}</div>
            </div>
            <div>
              <div class="text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">Memory</div>
              <div class="mt-1 font-display text-3xl">{Map.get(@stats, :memories, 0)}</div>
            </div>
            <div>
              <div class="text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">Turns</div>
              <div class="mt-1 font-display text-3xl">{Map.get(@stats, :turns, 0)}</div>
            </div>
            <div>
              <div class="text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">Providers</div>
              <div class="mt-1 font-display text-3xl">{Map.get(@stats, :providers, 0)}</div>
            </div>
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

  defp nav_link(assigns) do
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
      <span class="text-[var(--hx-accent)] transition group-hover:translate-x-1">+</span>
    </.link>
    """
  end
end
