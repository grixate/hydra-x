defmodule HydraXWeb.BoardLive.Show do
  use HydraXWeb, :live_view

  alias HydraX.Product
  alias HydraX.Product.BoardPromotion
  alias HydraX.Product.MyWork
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraXWeb.ProductShell

  @impl true
  def mount(%{"project_id" => project_id, "id" => session_id}, _session, socket) do
    project = Product.get_project!(project_id)
    session = Product.get_project_board_session!(project_id, session_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, ProductPubSub.project_topic(project.id))
      Phoenix.PubSub.subscribe(HydraX.PubSub, ProductPubSub.board_session_topic(session.id))
    end

    counts = MyWork.counts(project.id)
    board_sessions = Product.list_board_sessions(project.id, status: "active")
    agents = load_agents(project)

    {:ok,
     socket
     |> assign(:page_title, "#{session.title} - #{project.name}")
     |> assign(:current_page, "board_show")
     |> assign(:project, project)
     |> assign(:session, session)
     |> assign(:board_nodes, session.board_nodes || [])
     |> assign(:board_edges, session.board_edges || [])
     |> assign(:selected_node, nil)
     |> assign(:my_work_counts, counts)
     |> assign(:board_sessions, board_sessions)
     |> assign(:agents, agents)
     |> assign(:show_add_node, false)
     |> assign(:new_node_type, "insight")}
  end

  @impl true
  def handle_event("toggle_add_node", _params, socket) do
    {:noreply, assign(socket, :show_add_node, !socket.assigns.show_add_node)}
  end

  def handle_event("create_node", params, socket) do
    session = socket.assigns.session

    attrs = %{
      "node_type" => params["node_type"],
      "title" => params["title"],
      "body" => params["body"] || "",
      "created_by" => "human"
    }

    case Product.create_board_node(session.id, attrs) do
      {:ok, _node} ->
        refreshed = Product.get_board_session!(session.id)

        {:noreply,
         socket
         |> assign(:board_nodes, refreshed.board_nodes)
         |> assign(:show_add_node, false)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create node")}
    end
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.board_nodes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :selected_node, node)}
  end

  def handle_event("deselect_node", _params, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("promote_node", %{"id" => id}, socket) do
    case BoardPromotion.promote_node(String.to_integer(id)) do
      {:ok, _promoted} ->
        refreshed = Product.get_board_session!(socket.assigns.session.id)

        {:noreply,
         socket
         |> assign(:board_nodes, refreshed.board_nodes)
         |> assign(:selected_node, nil)
         |> put_flash(:info, "Node promoted to graph")}

      {:error, :not_draft} ->
        {:noreply, put_flash(socket, :error, "Node is not in draft status")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Promotion failed")}
    end
  end

  def handle_event("discard_node", %{"id" => id}, socket) do
    node = Product.get_board_node!(String.to_integer(id))

    case Product.update_board_node(node, %{"status" => "discarded"}) do
      {:ok, _} ->
        refreshed = Product.get_board_session!(socket.assigns.session.id)
        {:noreply, assign(socket, :board_nodes, refreshed.board_nodes)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not discard node")}
    end
  end

  def handle_event("complete_session", _params, socket) do
    session = socket.assigns.session

    case Product.update_board_session(session, %{"status" => "completed"}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:session, updated)
         |> put_flash(:info, "Session completed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not complete session")}
    end
  end

  def handle_event("promote_all", _params, socket) do
    session = socket.assigns.session
    draft_ids = socket.assigns.board_nodes |> Enum.filter(&(&1.status == "draft")) |> Enum.map(& &1.id)

    case BoardPromotion.promote_batch(session.id, draft_ids) do
      {:ok, _results} ->
        refreshed = Product.get_board_session!(session.id)

        {:noreply,
         socket
         |> assign(:board_nodes, refreshed.board_nodes)
         |> put_flash(:info, "#{length(draft_ids)} nodes promoted to graph")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Batch promotion failed")}
    end
  end

  @impl true
  def handle_info({:product_project_event, "board_node." <> _, _payload}, socket) do
    refreshed = Product.get_board_session!(socket.assigns.session.id)

    {:noreply,
     socket
     |> assign(:board_nodes, refreshed.board_nodes)
     |> assign(:board_edges, refreshed.board_edges)}
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
      board_sessions={@board_sessions}
      agents={@agents}
      my_work_counts={@my_work_counts}
      flash={@flash}
    >
      <div class="space-y-6">
        <%!-- Session header --%>
        <div class="flex items-center justify-between">
          <div>
            <.link
              navigate={~p"/projects/#{@project.id}/board"}
              class="text-xs text-[var(--hx-mute)] hover:text-white transition"
            >
              Board
            </.link>
            <h2 class="mt-1 font-display text-2xl">{@session.title}</h2>
            <p :if={@session.description} class="mt-1 text-sm text-white/50">
              {@session.description}
            </p>
          </div>
          <div class="flex gap-2">
            <button
              :if={@session.status == "active" and draft_count(@board_nodes) > 0}
              phx-click="promote_all"
              class="rounded-xl border border-green-500/30 bg-green-500/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.15em] text-green-400 hover:bg-green-500/20 transition"
            >
              Promote all ({draft_count(@board_nodes)})
            </button>
            <button
              :if={@session.status == "active"}
              phx-click="complete_session"
              class="rounded-xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.15em] text-[var(--hx-mute)] hover:bg-white/10 hover:text-white transition"
            >
              Complete session
            </button>
          </div>
        </div>

        <%!-- Stats bar --%>
        <div class="flex gap-6 text-xs text-[var(--hx-mute)]">
          <span>Status: <span class="text-white">{@session.status}</span></span>
          <span>Draft: <span class="text-white">{draft_count(@board_nodes)}</span></span>
          <span>Promoted: <span class="text-white">{promoted_count(@board_nodes)}</span></span>
          <span>Total: <span class="text-white">{length(@board_nodes)}</span></span>
        </div>

        <%!-- Add node button + form --%>
        <div :if={@session.status == "active"}>
          <button
            :if={!@show_add_node}
            phx-click="toggle_add_node"
            class="rounded-xl border border-dashed border-white/20 px-4 py-3 text-xs text-[var(--hx-mute)] hover:border-white/40 hover:text-white transition w-full"
          >
            + Add a node
          </button>

          <form :if={@show_add_node} phx-submit="create_node" class="glass-panel rounded-xl border border-white/10 p-5 space-y-4">
            <div class="flex gap-3">
              <select
                name="node_type"
                class="rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-xs text-white"
              >
                <option :for={type <- node_types()} value={type}>{humanize_type(type)}</option>
              </select>
              <input
                type="text"
                name="title"
                placeholder="Node title..."
                autofocus
                class="flex-1 rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-white placeholder-white/30 focus:border-[var(--hx-accent)] focus:outline-none"
              />
            </div>
            <textarea
              name="body"
              placeholder="Description..."
              rows="3"
              class="w-full rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-white placeholder-white/30 focus:border-[var(--hx-accent)] focus:outline-none resize-none"
            />
            <div class="flex gap-2 justify-end">
              <button
                type="button"
                phx-click="toggle_add_node"
                class="rounded-lg border border-white/10 px-4 py-2 text-xs text-[var(--hx-mute)] hover:text-white transition"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-lg bg-[var(--hx-accent)] px-6 py-2 font-mono text-xs uppercase text-white hover:bg-[var(--hx-accent)]/80 transition"
              >
                Create
              </button>
            </div>
          </form>
        </div>

        <%!-- Board nodes grid --%>
        <div class="grid gap-4 md:grid-cols-2">
          <div
            :for={node <- @board_nodes}
            phx-click="select_node"
            phx-value-id={node.id}
            class={[
              "cursor-pointer rounded-xl border px-5 py-4 transition",
              node_border_style(node, @selected_node)
            ]}
          >
            <div class="flex items-start justify-between">
              <div>
                <div class="flex items-center gap-2">
                  <span class="rounded px-2 py-0.5 text-[10px] uppercase bg-white/10 text-[var(--hx-mute)]">
                    {humanize_type(node.node_type)}
                  </span>
                  <span class={["rounded px-2 py-0.5 text-[10px] uppercase", node_status_style(node.status)]}>
                    {node.status}
                  </span>
                </div>
                <h3 class="mt-2 text-sm font-medium text-white">{node.title}</h3>
              </div>
            </div>
            <p :if={node.body} class="mt-2 text-xs text-white/50 line-clamp-2">{node.body}</p>
            <div class="mt-3 flex items-center justify-between text-[10px] text-[var(--hx-mute)]">
              <span>{node.created_by}</span>
              <div :if={node.status == "draft" and @session.status == "active"} class="flex gap-2">
                <button
                  phx-click="promote_node"
                  phx-value-id={node.id}
                  class="text-green-400 hover:text-green-300 transition"
                >
                  Promote
                </button>
                <button
                  phx-click="discard_node"
                  phx-value-id={node.id}
                  class="text-red-400 hover:text-red-300 transition"
                >
                  Discard
                </button>
              </div>
            </div>
          </div>
        </div>

        <div :if={@board_nodes == []} class="text-center py-16">
          <p class="text-[var(--hx-mute)]">No nodes in this session yet. Add a node or start a conversation with an agent.</p>
        </div>

        <%!-- Selected node detail --%>
        <div :if={@selected_node} class="glass-panel rounded-xl border border-[var(--hx-accent)]/30 p-6">
          <div class="flex items-start justify-between">
            <div>
              <div class="font-mono text-[10px] uppercase tracking-[0.25em] text-[var(--hx-mute)]">
                {humanize_type(@selected_node.node_type)} · {@selected_node.status}
              </div>
              <h3 class="mt-1 text-lg font-medium text-white">{@selected_node.title}</h3>
            </div>
            <button phx-click="deselect_node" class="text-[var(--hx-mute)] hover:text-white transition">
              x
            </button>
          </div>
          <p class="mt-4 text-sm text-white/70 whitespace-pre-wrap">{@selected_node.body}</p>
          <div class="mt-4 flex gap-4 text-xs text-[var(--hx-mute)]">
            <span>Created by: {@selected_node.created_by}</span>
            <span>Created: {Calendar.strftime(@selected_node.inserted_at, "%b %d, %H:%M")}</span>
            <span :if={@selected_node.promoted_node_id}>
              Promoted as: {@selected_node.promoted_node_type} #{@selected_node.promoted_node_id}
            </span>
          </div>
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

  defp node_types do
    ~w(insight decision strategy requirement design_node architecture_node task learning)
  end

  defp humanize_type("design_node"), do: "Design"
  defp humanize_type("architecture_node"), do: "Architecture"
  defp humanize_type(type), do: type |> String.replace("_", " ") |> String.capitalize()

  defp draft_count(nodes), do: Enum.count(nodes, &(&1.status == "draft"))
  defp promoted_count(nodes), do: Enum.count(nodes, &(&1.status == "promoted"))

  defp node_border_style(node, selected_node) do
    if selected_node && selected_node.id == node.id do
      "border-[var(--hx-accent)] bg-[rgba(245,110,66,0.08)]"
    else
      "border-white/10 bg-white/5 hover:border-white/20"
    end
  end

  defp node_status_style("draft"), do: "bg-yellow-500/20 text-yellow-400"
  defp node_status_style("promoted"), do: "bg-green-500/20 text-green-400"
  defp node_status_style("discarded"), do: "bg-red-500/20 text-red-400"
  defp node_status_style(_), do: "bg-white/10 text-[var(--hx-mute)]"
end
