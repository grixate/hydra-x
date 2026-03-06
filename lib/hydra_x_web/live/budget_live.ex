defmodule HydraXWeb.BudgetLive do
  use HydraXWeb, :live_view

  alias HydraX.Budget
  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    agent = Runtime.ensure_default_agent!()
    policy = Budget.ensure_policy!(agent.id)

    {:ok,
     socket
     |> assign(:page_title, "Budget")
     |> assign(:current, "budget")
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:policy, policy)
     |> assign(:status, Runtime.budget_status())
     |> assign(:form, to_form(Budget.change_policy(policy)))}
  end

  @impl true
  def handle_event("save", %{"policy" => params}, socket) do
    params = Map.put(params, "agent_id", socket.assigns.agent.id)

    case Budget.save_policy(socket.assigns.policy, params) do
      {:ok, policy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Budget policy updated")
         |> assign(:policy, policy)
         |> assign(:status, Runtime.budget_status())
         |> assign(:form, to_form(Budget.change_policy(policy)))
         |> assign(:stats, stats())}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[0.9fr_1.1fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Budget policy</div>
          <h2 class="mt-3 font-display text-4xl">Token guardrails</h2>
          <p class="mt-3 max-w-xl text-sm text-[var(--hx-mute)]">
            Every LLM completion now runs through a preflight budget check. Soft warnings are logged, and hard-limit breaches either warn or reject depending on the selected policy.
          </p>
          <.form for={@form} phx-submit="save" class="mt-6 space-y-2">
            <.input field={@form[:daily_limit]} type="number" label="Daily limit" />
            <.input field={@form[:conversation_limit]} type="number" label="Per-conversation limit" />
            <.input
              field={@form[:soft_warning_at]}
              type="number"
              step="0.01"
              label="Soft warning threshold"
            />
            <.input
              field={@form[:hard_limit_action]}
              type="select"
              label="Hard limit action"
              options={[{"Reject", "reject"}, {"Warn only", "warn"}]}
            />
            <.input field={@form[:enabled]} type="checkbox" label="Enable budget enforcement" />
            <div class="pt-2">
              <.button>Save budget policy</.button>
            </div>
          </.form>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Current usage</div>
          <div class="mt-6 grid gap-3 md:grid-cols-2">
            <div class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Daily
              </div>
              <div class="mt-3 font-display text-4xl">
                {(@status.usage && @status.usage.daily_tokens) || 0}
              </div>
            </div>
            <div class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Recent safety events
              </div>
              <div class="mt-3 font-display text-4xl">{length(@status.safety_events)}</div>
            </div>
          </div>

          <div class="mt-6 space-y-3">
            <div
              :for={event <- @status.safety_events}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex items-center justify-between gap-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                  {event.category}
                </div>
                <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  {event.level}
                </span>
              </div>
              <p class="mt-3 text-sm">{event.message}</p>
            </div>
            <div
              :if={@status.safety_events == []}
              class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
            >
              No safety events recorded yet.
            </div>
          </div>
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
