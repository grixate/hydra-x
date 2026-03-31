defmodule HydraXWeb.StreamLive do
  use HydraXWeb, :live_view

  alias HydraX.Product
  alias HydraX.Product.MyWork
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Product.Stream, as: ProductStream
  alias HydraXWeb.ProductShell

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    project = Product.get_project!(project_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, ProductPubSub.project_topic(project.id))
    end

    my_work = MyWork.generate(project.id)
    stream_data = ProductStream.generate_stream(project.id)
    counts = MyWork.counts(project.id)
    board_sessions = Product.list_board_sessions(project.id, status: "active")
    agents = load_agents(project)

    {:ok,
     socket
     |> assign(:page_title, "Stream - #{project.name}")
     |> assign(:current_page, "stream")
     |> assign(:project, project)
     |> assign(:tab, "my_work")
     |> assign(:my_work, my_work)
     |> assign(:stream_data, stream_data)
     |> assign(:my_work_counts, counts)
     |> assign(:board_sessions, board_sessions)
     |> assign(:agents, agents)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_info({:product_project_event, _event, _payload}, socket) do
    project = socket.assigns.project
    my_work = MyWork.generate(project.id)
    stream_data = ProductStream.generate_stream(project.id)
    counts = MyWork.counts(project.id)

    {:noreply,
     socket
     |> assign(:my_work, my_work)
     |> assign(:stream_data, stream_data)
     |> assign(:my_work_counts, counts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ProductShell.shell
      current={@current_page}
      project={@project}
      board_sessions={@board_sessions}
      agents={@agents}
      my_work_counts={@my_work_counts}
      flash={@flash}
    >
      <div class="space-y-6">
        <%!-- Tab toggle --%>
        <div class="flex gap-1 rounded-xl border border-white/10 bg-white/5 p-1 w-fit">
          <button
            phx-click="switch_tab"
            phx-value-tab="my_work"
            class={[
              "rounded-lg px-4 py-2 font-mono text-xs uppercase tracking-[0.15em] transition",
              if(@tab == "my_work",
                do: "bg-[var(--hx-accent)] text-white",
                else: "text-[var(--hx-mute)] hover:text-white"
              )
            ]}
          >
            My Work
            <span :if={@my_work_counts.needs_input > 0} class="ml-1 text-[10px]">
              ({@my_work_counts.needs_input})
            </span>
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="project"
            class={[
              "rounded-lg px-4 py-2 font-mono text-xs uppercase tracking-[0.15em] transition",
              if(@tab == "project",
                do: "bg-[var(--hx-accent)] text-white",
                else: "text-[var(--hx-mute)] hover:text-white"
              )
            ]}
          >
            Project
          </button>
        </div>

        <%!-- My Work tab --%>
        <div :if={@tab == "my_work"} class="space-y-8">
          <%!-- Needs your input --%>
          <section :if={@my_work.needs_input != []}>
            <h2 class="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">
              Needs your input ({length(@my_work.needs_input)})
            </h2>
            <div class="grid gap-3">
              <div
                :for={item <- @my_work.needs_input}
                class="glass-panel rounded-xl border border-white/10 px-5 py-4"
              >
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <div class="text-sm font-medium text-white">{item.title}</div>
                    <div class="mt-1 text-xs text-[var(--hx-mute)]">
                      {item.type} · {relative_time(item.created_at)}
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <span
                      :for={action <- item.actions}
                      class="rounded-lg border border-white/10 bg-white/5 px-3 py-1 text-[10px] uppercase tracking-wider text-[var(--hx-mute)] hover:bg-white/10 hover:text-white transition cursor-pointer"
                    >
                      {action}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <%!-- Active work --%>
          <section :if={@my_work.active_work != []}>
            <h2 class="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">
              Active work ({length(@my_work.active_work)})
            </h2>
            <div class="grid gap-3">
              <div
                :for={item <- @my_work.active_work}
                class="glass-panel rounded-xl border border-white/10 px-5 py-4"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-medium text-white">{item.title}</span>
                      <span :if={item[:priority]} class={[
                        "rounded px-2 py-0.5 text-[10px] uppercase",
                        priority_color(item[:priority])
                      ]}>
                        {item[:priority]}
                      </span>
                    </div>
                    <div class="mt-1 text-xs text-[var(--hx-mute)]">
                      {item.type}
                      <span :if={item[:status]}> · {item[:status]}</span>
                      <span :if={item[:draft_node_count]}> · {item[:draft_node_count]} draft nodes</span>
                    </div>
                  </div>
                  <.link
                    :if={item.type == "board_session"}
                    navigate={~p"/projects/#{@project.id}/board/#{item.session_id}"}
                    class="text-xs text-[var(--hx-accent)] hover:underline"
                  >
                    Open
                  </.link>
                </div>
              </div>
            </div>
          </section>

          <%!-- Recent output --%>
          <section :if={@my_work.recent_output != []}>
            <h2 class="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">
              Recent output (last 7 days)
            </h2>
            <div class="grid gap-2">
              <div
                :for={item <- @my_work.recent_output}
                class="flex items-center justify-between rounded-xl px-4 py-3 text-sm text-white/70 hover:bg-white/5 transition"
              >
                <span>{item.title}</span>
                <span class="text-xs text-[var(--hx-mute)]">{relative_time(item.at)}</span>
              </div>
            </div>
          </section>

          <div :if={@my_work.needs_input == [] and @my_work.active_work == [] and @my_work.recent_output == []} class="text-center py-12">
            <p class="text-[var(--hx-mute)]">Nothing here yet. Start a Board session to begin exploring.</p>
          </div>
        </div>

        <%!-- Project tab --%>
        <div :if={@tab == "project"} class="space-y-8">
          <section :if={@stream_data.right_now != []}>
            <h2 class="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">
              Right now ({length(@stream_data.right_now)})
            </h2>
            <div class="grid gap-3">
              <.stream_item :for={item <- @stream_data.right_now} item={item} />
            </div>
          </section>

          <section :if={@stream_data.recently != []}>
            <h2 class="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">
              Recently
            </h2>
            <div class="grid gap-3">
              <.stream_item :for={item <- @stream_data.recently} item={item} />
            </div>
          </section>

          <section :if={@stream_data.emerging != []}>
            <h2 class="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-[var(--hx-mute)]">
              Emerging
            </h2>
            <div class="grid gap-3">
              <.stream_item :for={item <- @stream_data.emerging} item={item} />
            </div>
          </section>

          <div :if={@stream_data.right_now == [] and @stream_data.recently == [] and @stream_data.emerging == []} class="text-center py-12">
            <p class="text-[var(--hx-mute)]">No project activity yet.</p>
          </div>
        </div>
      </div>
    </ProductShell.shell>
    """
  end

  attr :item, :map, required: true

  defp stream_item(assigns) do
    ~H"""
    <div class="glass-panel rounded-xl border border-white/10 px-5 py-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <div class="text-sm font-medium text-white">{@item.title}</div>
          <div class="mt-1 text-xs text-[var(--hx-mute)]">
            {@item.category} · {@item.node_type}
          </div>
        </div>
        <span class={[
          "rounded px-2 py-0.5 text-[10px] uppercase",
          urgency_color(@item.urgency)
        ]}>
          {@item.urgency}
        </span>
      </div>
      <p :if={@item.summary} class="mt-2 text-xs text-white/60">{@item.summary}</p>
    </div>
    """
  end

  defp load_agents(project) do
    [:researcher_agent, :strategist_agent, :architect_agent, :designer_agent, :memory_agent]
    |> Enum.map(fn key -> Map.get(project, key) end)
    |> Enum.reject(&is_nil/1)
  end

  defp priority_color("critical"), do: "bg-red-500/20 text-red-400"
  defp priority_color("high"), do: "bg-orange-500/20 text-orange-400"
  defp priority_color("medium"), do: "bg-yellow-500/20 text-yellow-400"
  defp priority_color("low"), do: "bg-blue-500/20 text-blue-400"
  defp priority_color(_), do: "bg-white/10 text-[var(--hx-mute)]"

  defp urgency_color("high"), do: "bg-red-500/20 text-red-400"
  defp urgency_color("medium"), do: "bg-yellow-500/20 text-yellow-400"
  defp urgency_color(_), do: "bg-white/10 text-[var(--hx-mute)]"

  defp relative_time(nil), do: ""

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
