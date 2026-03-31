defmodule HydraXWeb.GraphLive do
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

    graph_data = Product.graph_data(project.id)
    counts = MyWork.counts(project.id)
    board_sessions = Product.list_board_sessions(project.id, status: "active")
    agents = load_agents(project)

    {:ok,
     socket
     |> assign(:page_title, "Graph - #{project.name}")
     |> assign(:current_page, "graph")
     |> assign(:project, project)
     |> assign(:graph_data, graph_data)
     |> assign(:selected_node, nil)
     |> assign(:filter_type, nil)
     |> assign(:my_work_counts, counts)
     |> assign(:board_sessions, board_sessions)
     |> assign(:agents, agents)}
  end

  @impl true
  def handle_event("select_node", %{"node-type" => type, "node-id" => id}, socket) do
    node = find_node(socket.assigns.graph_data, type, String.to_integer(id))
    {:noreply, assign(socket, :selected_node, node)}
  end

  def handle_event("deselect_node", _params, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    filter = if type == "", do: nil, else: type
    {:noreply, assign(socket, :filter_type, filter)}
  end

  @impl true
  def handle_info({:product_project_event, _event, _payload}, socket) do
    project = socket.assigns.project
    graph_data = Product.graph_data(project.id)
    {:noreply, assign(socket, :graph_data, graph_data)}
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
        <div class="flex items-center justify-between">
          <h2 class="font-display text-2xl">Product Graph</h2>
          <div class="flex gap-2">
            <select
              phx-change="filter_type"
              name="type"
              class="rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs text-white"
            >
              <option value="">All types</option>
              <option :for={type <- node_types()} value={type}>{humanize_type(type)}</option>
            </select>
          </div>
        </div>

        <%!-- Graph visualization area --%>
        <div class="glass-panel min-h-[500px] rounded-xl border border-white/10 p-6">
          <div
            id="graph-container"
            phx-hook="GraphVisualization"
            data-nodes={Jason.encode!(filtered_nodes(@graph_data, @filter_type))}
            data-edges={Jason.encode!(@graph_data.edges)}
            class="h-[500px] w-full"
          >
            <%!-- Fallback when JS hook not loaded --%>
            <div class="grid gap-4" id="graph-fallback">
              <%!-- Swimlane layout per node type --%>
              <div :for={type <- active_types(@graph_data, @filter_type)} class="space-y-3">
                <h3 class="font-mono text-[10px] uppercase tracking-[0.25em] text-[var(--hx-mute)]">
                  {humanize_type(type)}
                </h3>
                <div class="flex flex-wrap gap-3">
                  <div
                    :for={node <- nodes_of_type(@graph_data, type)}
                    phx-click="select_node"
                    phx-value-node-type={type}
                    phx-value-node-id={node.id}
                    class={[
                      "cursor-pointer rounded-xl border px-4 py-3 transition hover:border-[var(--hx-accent)]",
                      if(@selected_node && @selected_node.id == node.id && @selected_node.type == type,
                        do: "border-[var(--hx-accent)] bg-[rgba(245,110,66,0.12)]",
                        else: "border-white/10 bg-white/5"
                      )
                    ]}
                  >
                    <div class="text-sm font-medium text-white">{node.title}</div>
                    <div class="mt-1 text-[10px] text-[var(--hx-mute)]">{node.status}</div>
                  </div>
                </div>
              </div>

              <div :if={@graph_data.nodes == []} class="text-center py-16">
                <p class="text-[var(--hx-mute)]">Graph is empty. Promote nodes from a Board session to populate it.</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Selected node detail panel --%>
        <div :if={@selected_node} class="glass-panel rounded-xl border border-white/10 p-6">
          <div class="flex items-start justify-between">
            <div>
              <div class="font-mono text-[10px] uppercase tracking-[0.25em] text-[var(--hx-mute)]">
                {@selected_node.type}
              </div>
              <h3 class="mt-1 text-lg font-medium text-white">{@selected_node.title}</h3>
            </div>
            <button phx-click="deselect_node" class="text-[var(--hx-mute)] hover:text-white transition">
              x
            </button>
          </div>
          <p :if={@selected_node[:body]} class="mt-4 text-sm text-white/70 whitespace-pre-wrap">
            {@selected_node[:body]}
          </p>
          <div class="mt-4 flex gap-4 text-xs text-[var(--hx-mute)]">
            <span>Status: {@selected_node.status}</span>
            <span :if={@selected_node[:metadata]["promoted_from_session"]}>
              From board session #{@selected_node[:metadata]["promoted_from_session"]}
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

  defp filtered_nodes(graph_data, nil), do: graph_data.nodes
  defp filtered_nodes(graph_data, type), do: Enum.filter(graph_data.nodes, &(&1.type == type))

  defp active_types(graph_data, nil) do
    graph_data.nodes |> Enum.map(& &1.type) |> Enum.uniq()
  end

  defp active_types(_graph_data, type), do: [type]

  defp nodes_of_type(graph_data, type) do
    Enum.filter(graph_data.nodes, &(&1.type == type))
  end

  defp find_node(graph_data, type, id) do
    Enum.find(graph_data.nodes, fn n -> n.type == type && n.id == id end)
  end
end
