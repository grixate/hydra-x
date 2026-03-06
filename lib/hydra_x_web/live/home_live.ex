defmodule HydraXWeb.HomeLive do
  use HydraXWeb, :live_view

  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    conversations = Runtime.list_conversations(limit: 5)

    {:ok,
     socket
     |> assign(:page_title, "Hydra-X")
     |> assign(:current, "home")
     |> assign(:stats, stats())
     |> assign(:health, Runtime.health_snapshot())
     |> assign(:safety_status, Runtime.safety_status())
     |> assign(:conversations, conversations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 lg:grid-cols-[1.4fr_0.8fr]">
        <div class="glass-panel overflow-hidden">
          <div class="border-b border-white/10 px-6 py-6">
            <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
              Public preview foundation
            </div>
            <h2 class="mt-3 max-w-3xl font-display text-5xl leading-[0.95]">
              A single-node agent control plane with memory, supervision, and operator surfaces already wired.
            </h2>
            <p class="mt-4 max-w-2xl text-base text-[var(--hx-mute)]">
              This repository now boots as a real Phoenix application with SQLite persistence, agent processes, typed memory, CLI tasks, and the first management UI routes.
            </p>
            <div class="mt-6 flex flex-wrap gap-3">
              <.button navigate={~p"/setup"}>Configure runtime</.button>
              <.button
                navigate={~p"/conversations"}
                class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Inspect conversations
              </.button>
            </div>
          </div>
          <div class="grid gap-4 p-6 md:grid-cols-3">
            <article class="metric-card">
              <div class="metric-label">Runtime</div>
              <div class="metric-value">OTP</div>
              <p>
                Agent, channel, worker, cortex, and compactor primitives are registered under supervision.
              </p>
            </article>
            <article class="metric-card">
              <div class="metric-label">Memory</div>
              <div class="metric-value">{Memory.list_memories(limit: 1_000) |> length()}</div>
              <p>
                Typed graph records are persisted in SQLite and rendered back into workspace markdown.
              </p>
            </article>
            <article class="metric-card">
              <div class="metric-label">Preview</div>
              <div class="metric-value">UI + CLI</div>
              <p>
                Setup, health, providers, agents, conversations, and memory are exposed through the app shell.
              </p>
            </article>
          </div>
        </div>

        <div class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Health ledger</div>
          <div class="mt-4 grid gap-3">
            <div
              :for={check <- @health}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-3"
            >
              <div class="flex items-center justify-between gap-4">
                <div class="font-mono text-sm uppercase tracking-[0.18em]">{check.name}</div>
                <span class={status_class(check.status)}>{Atom.to_string(check.status)}</span>
              </div>
              <p class="mt-2 text-sm text-[var(--hx-mute)]">{check.detail}</p>
            </div>
          </div>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="flex items-end justify-between gap-4">
          <div>
            <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
              Recent conversations
            </div>
            <h3 class="mt-2 font-display text-3xl">Latest runtime activity</h3>
          </div>
          <.link
            navigate={~p"/conversations"}
            class="font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-accent)]"
          >
            Open log
          </.link>
        </div>

        <div class="mt-6 space-y-3">
          <div
            :if={@conversations == []}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
          >
            No conversations have been persisted yet. Use `mix hydra_x.chat -m "Hello"` or the setup screen to initialize the runtime.
          </div>

          <div
            :for={conversation <- @conversations}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div class="font-display text-2xl">
                  {conversation.title || "Untitled conversation"}
                </div>
                <div class="mt-1 text-sm text-[var(--hx-mute)]">
                  {conversation.channel} · {conversation.agent.name}
                </div>
              </div>
              <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {conversation.status}
              </span>
            </div>
          </div>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="flex items-end justify-between gap-4">
          <div>
            <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
              Safety events
            </div>
            <h3 class="mt-2 font-display text-3xl">Recent guardrail activity</h3>
          </div>
          <.link
            navigate={~p"/health"}
            class="font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-accent)]"
          >
            Open health
          </.link>
        </div>

        <div class="mt-6 grid gap-3 md:grid-cols-3">
          <article class="metric-card">
            <div class="metric-label">Errors</div>
            <div class="metric-value">{@safety_status.counts.error}</div>
            <p>Hard rejects, delivery failures, or blocked operations that need review.</p>
          </article>
          <article class="metric-card">
            <div class="metric-label">Warnings</div>
            <div class="metric-value">{@safety_status.counts.warn}</div>
            <p>Budget soft-limit notices and blocked tool attempts from the last 24 hours.</p>
          </article>
          <article class="metric-card">
            <div class="metric-label">Latest</div>
            <div class="metric-value">
              {@safety_status.recent_events |> List.first() |> then(&(&1 && &1.category)) || "clear"}
            </div>
            <p>Most recent safety category seen by the runtime.</p>
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
      memories: Memory.list_memories(limit: 1_000) |> length()
    }
  end

  defp status_class(:ok),
    do:
      "rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-emerald-300"

  defp status_class(:warn),
    do:
      "rounded-full border border-amber-400/20 bg-amber-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-amber-300"
end
