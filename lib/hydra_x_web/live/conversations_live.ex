defmodule HydraXWeb.ConversationsLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    conversations = Runtime.list_conversations(limit: 50)
    selected = conversations |> List.first() |> maybe_load()

    {:ok,
     socket
     |> assign(:page_title, "Conversations")
     |> assign(:current, "conversations")
     |> assign(:stats, stats())
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      case params["conversation_id"] do
        nil -> socket.assigns.selected
        id -> Runtime.get_conversation!(id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[0.8fr_1.2fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Conversations</div>
          <div class="mt-4 space-y-3">
            <.link
              :for={conversation <- @conversations}
              patch={~p"/conversations?#{[conversation_id: conversation.id]}"}
              class={[
                "block rounded-2xl border px-4 py-4 transition",
                if(@selected && @selected.id == conversation.id,
                  do: "border-[var(--hx-accent)] bg-[rgba(245,110,66,0.08)]",
                  else: "border-white/10 bg-black/10 hover:bg-white/5"
                )
              ]}
            >
              <div class="font-display text-2xl">{conversation.title || "Untitled"}</div>
              <div class="mt-1 text-sm text-[var(--hx-mute)]">
                {conversation.channel} · {conversation.agent.name}
              </div>
            </.link>
          </div>
        </article>

        <article class="glass-panel p-6">
          <div :if={@selected} class="space-y-4">
            <div class="border-b border-white/10 pb-4">
              <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Transcript</div>
              <h2 class="mt-3 font-display text-4xl">{@selected.title || "Untitled conversation"}</h2>
            </div>

            <div class="space-y-3">
              <div :for={turn <- @selected.turns} class="rounded-2xl border border-white/10 px-4 py-4">
                <div class="flex items-center justify-between gap-4">
                  <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                    {turn.role}
                  </span>
                  <span class="text-xs text-[var(--hx-mute)]">#{turn.sequence}</span>
                </div>
                <p class="mt-3 whitespace-pre-wrap text-sm leading-6">{turn.content}</p>
              </div>
            </div>
          </div>

          <div
            :if={is_nil(@selected)}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
          >
            No conversation selected.
          </div>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  defp maybe_load(nil), do: nil
  defp maybe_load(conversation), do: Runtime.get_conversation!(conversation.id)

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
