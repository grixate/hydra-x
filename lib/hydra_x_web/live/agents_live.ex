defmodule HydraXWeb.AgentsLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.AgentProfile
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Agents")
     |> assign(:current, "agents")
     |> assign(:stats, stats())
     |> assign(:agents, Runtime.list_agents())
     |> assign(:form, to_form(Runtime.change_agent(%AgentProfile{})))}
  end

  @impl true
  def handle_event("create", %{"agent_profile" => params}, socket) do
    case Runtime.save_agent(params) do
      {:ok, agent} ->
        HydraX.Agent.ensure_started(agent)

        {:noreply,
         socket
         |> put_flash(:info, "Agent created")
         |> assign(:agents, Runtime.list_agents())
         |> assign(:stats, stats())
         |> assign(:form, to_form(Runtime.change_agent(%AgentProfile{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    Runtime.toggle_agent_status!(id)

    {:noreply,
     socket
     |> assign(:agents, Runtime.list_agents())
     |> assign(:stats, stats())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[1.2fr_0.8fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Agent registry</div>
          <div class="mt-4 space-y-4">
            <div
              :for={agent <- @agents}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div class="font-display text-2xl">{agent.name}</div>
                  <div class="mt-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    {agent.slug}
                  </div>
                  <p class="mt-3 max-w-xl text-sm text-[var(--hx-mute)]">{agent.description}</p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    {agent.status}
                  </span>
                  <button
                    phx-click="toggle"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Toggle
                  </button>
                </div>
              </div>
              <div class="mt-3 text-sm text-[var(--hx-mute)]">{agent.workspace_root}</div>
            </div>
          </div>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">New agent</div>
          <.form for={@form} phx-submit="create" class="mt-6 space-y-2">
            <.input field={@form[:name]} label="Name" />
            <.input field={@form[:slug]} label="Slug" />
            <.input field={@form[:workspace_root]} label="Workspace root" />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <div class="pt-2">
              <.button>Create agent</.button>
            </div>
          </.form>
        </article>
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
