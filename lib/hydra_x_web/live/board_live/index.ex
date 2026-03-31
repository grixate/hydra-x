defmodule HydraXWeb.BoardLive.Index do
  use HydraXWeb, :live_view

  alias HydraX.Product
  alias HydraX.Product.MyWork
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraXWeb.ProductShell

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    project = Product.get_project!(project_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, ProductPubSub.project_topic(project.id))
    end

    board_sessions = Product.list_board_sessions(project.id)
    counts = MyWork.counts(project.id)
    agents = load_agents(project)

    {:ok,
     socket
     |> assign(:page_title, "Board - #{project.name}")
     |> assign(:current_page, "board")
     |> assign(:project, project)
     |> assign(:board_sessions, board_sessions)
     |> assign(:my_work_counts, counts)
     |> assign(:agents, agents)
     |> assign(:show_new_form, socket.params["new"] == "1")
     |> assign(:new_title, "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :show_new_form, params["new"] == "1")}
  end

  @impl true
  def handle_event("toggle_new_form", _params, socket) do
    {:noreply, assign(socket, :show_new_form, !socket.assigns.show_new_form)}
  end

  def handle_event("create_session", %{"title" => title}, socket) do
    project = socket.assigns.project

    case Product.create_board_session(project.id, %{"title" => title}) do
      {:ok, session} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/projects/#{project.id}/board/#{session.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create session")}
    end
  end

  @impl true
  def handle_info({:product_project_event, "board_session." <> _, _payload}, socket) do
    sessions = Product.list_board_sessions(socket.assigns.project.id)
    {:noreply, assign(socket, :board_sessions, sessions)}
  end

  def handle_info({:product_project_event, _event, _payload}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ProductShell.shell
      current={@current_page}
      project={@project}
      board_sessions={active_sessions(@board_sessions)}
      agents={@agents}
      my_work_counts={@my_work_counts}
      flash={@flash}
    >
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h2 class="font-display text-2xl">Board Sessions</h2>
          <button
            phx-click="toggle_new_form"
            class="rounded-xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.15em] text-[var(--hx-mute)] hover:bg-white/10 hover:text-white transition"
          >
            + New session
          </button>
        </div>

        <%!-- New session form --%>
        <form :if={@show_new_form} phx-submit="create_session" class="glass-panel rounded-xl border border-white/10 p-5">
          <div class="flex gap-3">
            <input
              type="text"
              name="title"
              placeholder="Session title..."
              value={@new_title}
              autofocus
              class="flex-1 rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-white placeholder-white/30 focus:border-[var(--hx-accent)] focus:outline-none"
            />
            <button
              type="submit"
              class="rounded-lg bg-[var(--hx-accent)] px-6 py-2 font-mono text-xs uppercase tracking-[0.15em] text-white hover:bg-[var(--hx-accent)]/80 transition"
            >
              Create
            </button>
          </div>
        </form>

        <%!-- Session cards --%>
        <div class="grid gap-4">
          <.link
            :for={session <- @board_sessions}
            navigate={~p"/projects/#{@project.id}/board/#{session.id}"}
            class="glass-panel rounded-xl border border-white/10 px-6 py-5 transition hover:border-white/20 hover:bg-white/5"
          >
            <div class="flex items-start justify-between">
              <div>
                <h3 class="text-lg font-medium text-white">{session.title}</h3>
                <p :if={session.description} class="mt-1 text-sm text-white/50">
                  {String.slice(session.description || "", 0..120)}
                </p>
              </div>
              <span class={[
                "rounded-lg px-3 py-1 text-[10px] uppercase tracking-wider",
                session_status_style(session.status)
              ]}>
                {session.status}
              </span>
            </div>
            <div class="mt-4 flex gap-6 text-xs text-[var(--hx-mute)]">
              <span>{draft_count(session)} draft nodes</span>
              <span>{Calendar.strftime(session.updated_at, "%b %d, %H:%M")}</span>
            </div>
          </.link>
        </div>

        <div :if={@board_sessions == []} class="text-center py-16">
          <p class="text-[var(--hx-mute)]">No board sessions yet. Create one to start exploring ideas.</p>
        </div>
      </div>
    </ProductShell.shell>
    """
  end

  defp load_agents(project) do
    [:researcher_agent, :strategist_agent, :architect_agent, :designer_agent, :memory_agent]
    |> Enum.map(fn key -> Map.get(project, key) end)
    |> Enum.reject(&is_nil/1)
  end

  defp active_sessions(sessions), do: Enum.filter(sessions, &(&1.status == "active"))

  defp session_status_style("active"), do: "bg-green-500/20 text-green-400"
  defp session_status_style("completed"), do: "bg-blue-500/20 text-blue-400"
  defp session_status_style("archived"), do: "bg-white/10 text-[var(--hx-mute)]"
  defp session_status_style(_), do: "bg-white/10 text-[var(--hx-mute)]"

  defp draft_count(%{board_nodes: nodes}) when is_list(nodes) do
    Enum.count(nodes, &(&1.status == "draft"))
  end

  defp draft_count(_), do: 0
end
