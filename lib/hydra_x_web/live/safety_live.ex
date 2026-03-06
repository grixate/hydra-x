defmodule HydraXWeb.SafetyLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    filters = default_filters()

    {:ok,
     socket
     |> assign(:page_title, "Safety")
     |> assign(:current, "safety")
     |> assign(:stats, stats())
     |> assign_safety(filters)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters =
      default_filters()
      |> Map.merge(params)

    {:noreply, socket |> assign(:stats, stats()) |> assign_safety(filters)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[0.85fr_1.15fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Safety ledger</div>
          <h2 class="mt-3 font-display text-4xl">Guardrail activity</h2>
          <p class="mt-3 max-w-xl text-sm text-[var(--hx-mute)]">
            Review recent policy violations, tool denials, provider failures, and gateway incidents without leaving the control plane.
          </p>

          <div class="mt-6 grid gap-3 md:grid-cols-3">
            <div class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Errors
              </div>
              <div class="mt-3 font-display text-4xl">{@safety.counts.error}</div>
            </div>
            <div class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Warnings
              </div>
              <div class="mt-3 font-display text-4xl">{@safety.counts.warn}</div>
            </div>
            <div class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Informational
              </div>
              <div class="mt-3 font-display text-4xl">{@safety.counts.info}</div>
            </div>
          </div>

          <.form for={@form} phx-submit="filter" class="mt-6 space-y-2">
            <.input
              field={@form[:level]}
              type="select"
              label="Level"
              options={[{"All levels", ""}, {"Error", "error"}, {"Warn", "warn"}, {"Info", "info"}]}
            />
            <.input
              field={@form[:category]}
              type="select"
              label="Category"
              options={[{"All categories", ""} | Enum.map(@safety.categories, &{&1, &1})]}
            />
            <.input field={@form[:limit]} type="number" label="Rows" min="1" max="100" />
            <div class="pt-2">
              <.button>Apply filters</.button>
            </div>
          </.form>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Recent events</div>
          <div class="mt-6 space-y-3">
            <div
              :for={event <- @safety.recent_events}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <div class="font-display text-2xl">{event.category}</div>
                  <div class="mt-1 text-sm text-[var(--hx-mute)]">
                    {event.agent && event.agent.name} · {format_datetime(event.inserted_at)}
                  </div>
                </div>
                <span class={[
                  "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                  level_class(event.level)
                ]}>
                  {event.level}
                </span>
              </div>
              <p class="mt-3 text-sm">{event.message}</p>
              <div class="mt-3 flex flex-wrap gap-2 text-xs text-[var(--hx-mute)]">
                <span
                  :if={event.conversation_id}
                  class="rounded-full border border-white/10 px-3 py-1"
                >
                  conversation {event.conversation_id}
                </span>
                <span
                  :if={event.metadata["reason"]}
                  class="rounded-full border border-white/10 px-3 py-1"
                >
                  {event.metadata["reason"]}
                </span>
              </div>
            </div>
            <div
              :if={@safety.recent_events == []}
              class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
            >
              No safety events match the current filter.
            </div>
          </div>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  defp assign_safety(socket, filters) do
    limit =
      filters["limit"]
      |> to_string()
      |> Integer.parse()
      |> case do
        {value, _} when value > 0 -> min(value, 100)
        _ -> 25
      end

    safety =
      Runtime.safety_status(
        limit: limit,
        level: blank_to_nil(filters["level"]),
        category: blank_to_nil(filters["category"])
      )

    socket
    |> assign(:filters, Map.put(filters, "limit", to_string(limit)))
    |> assign(:safety, safety)
    |> assign(:form, to_form(filters, as: :filters))
  end

  defp default_filters do
    %{"level" => "", "category" => "", "limit" => "25"}
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp level_class("error"), do: "border-rose-400/30 bg-rose-400/10 text-rose-200"
  defp level_class("warn"), do: "border-amber-400/30 bg-amber-400/10 text-amber-200"
  defp level_class(_), do: "border-cyan-400/30 bg-cyan-400/10 text-cyan-200"

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
