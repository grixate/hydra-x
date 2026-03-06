defmodule HydraXWeb.HealthLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Health")
     |> assign(:current, "health")
     |> assign(:stats, stats())
     |> assign(:checks, Runtime.health_snapshot())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="glass-panel p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Runtime health</div>
        <h2 class="mt-3 font-display text-4xl">Operational snapshot</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={check <- @checks}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {check.name}
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                if(check.status == :ok,
                  do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                  else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                )
              ]}>
                {check.status}
              </span>
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">{check.detail}</p>
          </article>
        </div>
      </section>
    </AppShell.shell>
    """
  end

  defp stats do
    %{
      agents: Runtime.list_agents() |> length(),
      providers: Runtime.list_provider_configs() |> length(),
      turns:
        Runtime.list_conversations(limit: 200)
        |> Enum.flat_map(&Runtime.list_turns(&1.id))
        |> length(),
      memories: HydraX.Memory.list_memories(limit: 1_000) |> length()
    }
  end
end
