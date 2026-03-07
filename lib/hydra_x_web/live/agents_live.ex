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
     |> assign(:agents, agents_with_runtime())
     |> assign(:editing_agent, %AgentProfile{})
     |> assign(:form, to_form(Runtime.change_agent(%AgentProfile{})))}
  end

  @impl true
  def handle_event("save", %{"agent_profile" => params}, socket) do
    action = if socket.assigns.editing_agent.id, do: "updated", else: "created"

    case Runtime.save_agent(socket.assigns.editing_agent, params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent #{action}")
         |> assign(:agents, agents_with_runtime())
         |> assign(:stats, stats())
         |> assign(:editing_agent, %AgentProfile{})
         |> assign(:form, to_form(Runtime.change_agent(%AgentProfile{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    agent = Runtime.get_agent!(id)

    {:noreply,
     socket
     |> assign(:editing_agent, agent)
     |> assign(:form, to_form(Runtime.change_agent(agent)))}
  end

  def handle_event("reset_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_agent, %AgentProfile{})
     |> assign(:form, to_form(Runtime.change_agent(%AgentProfile{})))}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    Runtime.toggle_agent_status!(id)

    {:noreply,
     socket
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("set_default", %{"id" => id}, socket) do
    Runtime.set_default_agent!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Default agent updated")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("repair_workspace", %{"id" => id}, socket) do
    Runtime.repair_agent_workspace!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Workspace template repaired")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("refresh_bulletin", %{"id" => id}, socket) do
    Runtime.refresh_agent_bulletin!(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(:info, "Agent bulletin refreshed")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("start_runtime", %{"id" => id}, socket) do
    Runtime.start_agent_runtime!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Agent runtime started")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("stop_runtime", %{"id" => id}, socket) do
    Runtime.stop_agent_runtime!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Agent runtime stopped")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("restart_runtime", %{"id" => id}, socket) do
    Runtime.restart_agent_runtime!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Agent runtime restarted")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("reconcile_runtime", _params, socket) do
    summary = Runtime.reconcile_agents!()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Runtime reconciled (started #{summary.started}, stopped #{summary.stopped})"
     )
     |> assign(:agents, agents_with_runtime())
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
                  <span
                    :if={agent.is_default}
                    class="rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-emerald-300"
                  >
                    default
                  </span>
                  <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    {agent.status}
                  </span>
                  <span class={[
                    "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                    if(agent.runtime.running,
                      do: "border-cyan-400/20 bg-cyan-400/10 text-cyan-200",
                      else: "border-white/10 text-[var(--hx-mute)]"
                    )
                  ]}>
                    {if agent.runtime.running, do: "runtime up", else: "runtime down"}
                  </span>
                  <button
                    phx-click="edit"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Edit
                  </button>
                  <button
                    :if={!agent.is_default}
                    phx-click="set_default"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Make default
                  </button>
                  <button
                    phx-click="repair_workspace"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Repair workspace
                  </button>
                  <button
                    :if={!agent.runtime.running}
                    phx-click="start_runtime"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Start runtime
                  </button>
                  <button
                    :if={agent.runtime.running}
                    phx-click="stop_runtime"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Stop runtime
                  </button>
                  <button
                    phx-click="restart_runtime"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Restart runtime
                  </button>
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
              <div :if={agent.runtime.pid} class="mt-2 font-mono text-xs text-[var(--hx-mute)]">
                {agent.runtime.pid}
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="flex items-center justify-between gap-3">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Bulletin
                  </div>
                  <button
                    phx-click="refresh_bulletin"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Refresh bulletin
                  </button>
                </div>
                <p class="mt-3 whitespace-pre-wrap text-sm text-[var(--hx-mute)]">
                  {agent.bulletin.content || "No bulletin yet"}
                </p>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  {agent.bulletin.memory_count} memory items in bulletin scope
                </div>
              </div>
            </div>
          </div>
          <div class="mt-6">
            <button
              type="button"
              phx-click="reconcile_runtime"
              class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
            >
              Reconcile runtimes
            </button>
          </div>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            {if @editing_agent.id, do: "Edit agent", else: "New agent"}
          </div>
          <.form for={@form} phx-submit="save" class="mt-6 space-y-2">
            <.input field={@form[:name]} label="Name" />
            <.input field={@form[:slug]} label="Slug" />
            <.input field={@form[:workspace_root]} label="Workspace root" />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <.input field={@form[:is_default]} type="checkbox" label="Default agent" />
            <div class="pt-2">
              <.button>{if @editing_agent.id, do: "Save agent", else: "Create agent"}</.button>
              <button
                :if={@editing_agent.id}
                type="button"
                phx-click="reset_form"
                class="ml-3 inline-flex items-center rounded-2xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.18em] text-white transition hover:bg-white/10"
              >
                New agent
              </button>
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

  defp agents_with_runtime do
    Runtime.list_agents()
    |> Enum.map(fn agent ->
      agent
      |> Map.put(:runtime, Runtime.agent_runtime_status(agent))
      |> Map.put(:bulletin, Runtime.agent_bulletin(agent.id))
    end)
  end
end
