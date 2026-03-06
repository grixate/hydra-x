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
     |> assign(:checks, Runtime.health_snapshot())
     |> assign(:telegram_status, Runtime.telegram_status())
     |> assign(:safety_status, Runtime.safety_status())}
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

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Telegram</div>
        <h2 class="mt-3 font-display text-4xl">Channel readiness</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Webhook URL
            </div>
            <p class="mt-3 break-all text-sm text-[var(--hx-accent)]">
              {@telegram_status.webhook_url}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Binding
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {(@telegram_status.bot_username && "@#{@telegram_status.bot_username}") ||
                "unconfigured"}
              {if @telegram_status.default_agent_name,
                do: " -> #{@telegram_status.default_agent_name}",
                else: ""}
            </p>
            <p :if={@telegram_status.registered_at} class="mt-2 text-xs text-[var(--hx-mute)]">
              Registered at {Calendar.strftime(
                @telegram_status.registered_at,
                "%Y-%m-%d %H:%M:%S UTC"
              )}
            </p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Safety ledger</div>
        <h2 class="mt-3 font-display text-4xl">Recent runtime events</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-3">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Errors
            </div>
            <div class="mt-3 font-display text-4xl">{@safety_status.counts.error}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Warnings
            </div>
            <div class="mt-3 font-display text-4xl">{@safety_status.counts.warn}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Info
            </div>
            <div class="mt-3 font-display text-4xl">{@safety_status.counts.info}</div>
          </article>
        </div>

        <div class="mt-6 space-y-3">
          <div
            :for={event <- @safety_status.recent_events}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                  {event.category}
                </div>
                <p class="mt-2 text-sm">{event.message}</p>
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                level_class(event.level)
              ]}>
                {event.level}
              </span>
            </div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              {event.agent && event.agent.name}
              {if event.conversation,
                do: " · #{event.conversation.title || event.conversation.channel}",
                else: ""}
            </p>
          </div>
          <div
            :if={@safety_status.recent_events == []}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
          >
            No recent safety events.
          </div>
        </div>
      </section>
    </AppShell.shell>
    """
  end

  defp level_class("error"), do: "border-rose-400/20 bg-rose-400/10 text-rose-300"
  defp level_class("warn"), do: "border-amber-400/20 bg-amber-400/10 text-amber-300"
  defp level_class(_), do: "border-white/10 bg-black/10 text-[var(--hx-mute)]"

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
