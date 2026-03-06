defmodule HydraXWeb.MemoryLive do
  use HydraXWeb, :live_view

  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(params, _session, socket) do
    query = Map.get(params, "q", "")

    {:ok,
     socket
     |> assign(:page_title, "Memory")
     |> assign(:current, "memory")
     |> assign(:stats, stats())
     |> assign(:query, query)
     |> assign(:memories, load_memories(query))}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:memories, load_memories(query))}
  end

  def handle_event("sync", _params, socket) do
    if agent = Runtime.get_default_agent() do
      Memory.sync_markdown(agent)
    end

    {:noreply, put_flash(socket, :info, "Memory markdown synced")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="glass-panel p-6">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
              Typed graph memory
            </div>
            <h2 class="mt-3 font-display text-4xl">Authoritative memory store</h2>
          </div>
          <button
            phx-click="sync"
            class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
          >
            Sync markdown view
          </button>
        </div>

        <form phx-submit="search" class="mt-6 max-w-xl">
          <label class="input w-full border-white/10 bg-black/10">
            <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Query
            </span>
            <input
              type="text"
              name="q"
              value={@query}
              placeholder="Recall preferences, decisions, goals..."
            />
          </label>
        </form>

        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={memory <- @memories}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                {memory.type}
              </span>
              <span class="text-xs text-[var(--hx-mute)]">
                importance {Float.round(memory.importance, 2)}
              </span>
            </div>
            <p class="mt-3 text-sm leading-6">{memory.content}</p>
          </article>
        </div>
      </section>
    </AppShell.shell>
    """
  end

  defp load_memories(""), do: Memory.list_memories(limit: 100)
  defp load_memories(query), do: Memory.search(nil, query, 100)

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
end
