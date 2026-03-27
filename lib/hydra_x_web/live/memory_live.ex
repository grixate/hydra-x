defmodule HydraXWeb.MemoryLive do
  use HydraXWeb, :live_view

  alias HydraX.Memory
  alias HydraX.Memory.{Edge, Entry}
  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(HydraX.PubSub, "memory")

    filters =
      default_filters()
      |> Map.put("query", Map.get(params, "q", ""))

    {memories, memory_rankings, has_next} = load_memories_paginated(filters, 1)
    selected = List.first(memories)

    {:ok,
     socket
     |> assign(:page_title, "Memory")
     |> assign(:current, "memory")
     |> assign(:stats, stats())
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> assign(:has_next, has_next)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:agents, Runtime.list_agents())
     |> assign(:memory_types, memory_types())
     |> assign(:memory_statuses, memory_statuses())
     |> assign(:edge_kinds, edge_kinds())
     |> assign(:embedding_status, current_embedding_status(filters))
     |> assign(:ingest_agent, current_ingest_agent(filters))
     |> assign(:ingested_files, load_ingested_files(filters))
     |> assign(:hx_ingest_runs, load_hx_ingest_runs(filters))
     |> assign(:memories, memories)
     |> assign(:memory_rankings, memory_rankings)
     |> assign(:selected, selected)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
     |> assign(:edges, load_edges(selected))
     |> assign_form(:memory_form, memory_form(selected), :memory)
     |> assign_form(:edge_form, edge_form(selected), :edge)
     |> assign(:reconcile_form, reconcile_form(memories, selected))
     |> assign(:ingest_form, to_form(%{"filename" => "", "force" => "false"}, as: :ingest))
     |> assign(:archive_ingest_form, to_form(%{"filename" => ""}, as: :archive_ingest))}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    filters = Map.put(socket.assigns.filters, "query", query)
    {memories, memory_rankings} = load_memories(filters)

    selected =
      socket.assigns.selected && maybe_refresh_selection(memories, socket.assigns.selected.id)

    selected = selected || List.first(memories)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:memories, memories)
     |> assign(:memory_rankings, memory_rankings)
     |> assign(:embedding_status, current_embedding_status(filters))
     |> assign(:ingest_agent, current_ingest_agent(filters))
     |> assign(:ingested_files, load_ingested_files(filters))
     |> assign(:hx_ingest_runs, load_hx_ingest_runs(filters))
     |> assign(:selected, selected)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
     |> assign(:edges, load_edges(selected))
     |> assign_form(:memory_form, memory_form(selected), :memory)
     |> assign_form(:edge_form, edge_form(selected), :edge)
     |> assign(:reconcile_form, reconcile_form(memories, selected))}
  end

  def handle_event("filter_memories", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(params)

    {memories, memory_rankings} = load_memories(filters)

    selected =
      socket.assigns.selected && maybe_refresh_selection(memories, socket.assigns.selected.id)

    selected = selected || List.first(memories)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:memories, memories)
     |> assign(:memory_rankings, memory_rankings)
     |> assign(:embedding_status, current_embedding_status(filters))
     |> assign(:ingest_agent, current_ingest_agent(filters))
     |> assign(:ingested_files, load_ingested_files(filters))
     |> assign(:hx_ingest_runs, load_hx_ingest_runs(filters))
     |> assign(:selected, selected)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
     |> assign(:edges, load_edges(selected))
     |> assign_form(:memory_form, memory_form(selected), :memory)
     |> assign_form(:edge_form, edge_form(selected), :edge)
     |> assign(:reconcile_form, reconcile_form(memories, selected))}
  end

  def handle_event("sync", _params, socket) do
    if agent = Runtime.get_default_agent() do
      Memory.sync_markdown(agent)
    end

    {:noreply, put_flash(socket, :info, "Memory markdown synced")}
  end

  def handle_event("ingest_file", %{"ingest" => params}, socket) do
    with agent when not is_nil(agent) <- current_ingest_agent(socket.assigns.filters),
         filename = params["filename"],
         filename <- blank_to_nil(filename),
         true <- is_binary(filename) or {:error, :missing_filename},
         file_path <- Path.join([agent.workspace_root, "ingest", filename]),
         {:ok, result} <-
           Runtime.ingest_file(agent.id, file_path, force: truthy?(params["force"])) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         ingest_message(filename, result)
       )
       |> assign(:ingested_files, load_ingested_files(socket.assigns.filters))
       |> assign(:hx_ingest_runs, load_hx_ingest_runs(socket.assigns.filters))
       |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(socket.assigns.selected))
       |> assign(:stats, stats())}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Choose or create an agent first.")}

      {:error, :missing_filename} ->
        {:noreply, put_flash(socket, :error, "Enter a filename from the ingest directory.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Ingest failed: #{inspect(reason)}")}

      false ->
        {:noreply, put_flash(socket, :error, "Enter a filename from the ingest directory.")}
    end
  end

  def handle_event(
        "archive_ingest_file",
        %{"archive_ingest" => %{"filename" => filename}},
        socket
      ) do
    with agent when not is_nil(agent) <- current_ingest_agent(socket.assigns.filters),
         filename <- blank_to_nil(filename),
         true <- is_binary(filename) or {:error, :missing_filename},
         {:ok, count} <- Runtime.archive_file(agent.id, filename) do
      {:noreply,
       socket
       |> put_flash(:info, "Archived #{count} ingest-backed memories for #{filename}")
       |> assign(:ingested_files, load_ingested_files(socket.assigns.filters))
       |> assign(:hx_ingest_runs, load_hx_ingest_runs(socket.assigns.filters))
       |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(socket.assigns.selected))
       |> assign(:stats, stats())}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Choose or create an agent first.")}

      {:error, :missing_filename} ->
        {:noreply, put_flash(socket, :error, "Enter a filename to archive.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Archive failed: #{inspect(reason)}")}

      false ->
        {:noreply, put_flash(socket, :error, "Enter a filename to archive.")}
    end
  end

  def handle_event("select_memory", %{"id" => id}, socket) do
    memory = Memory.get_memory!(id)

    {:noreply,
     socket
     |> assign(:selected, memory)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(memory))
     |> assign(:edges, load_edges(memory))
     |> assign_form(:memory_form, memory_form(memory), :memory)
     |> assign_form(:edge_form, edge_form(memory), :edge)
     |> assign(:reconcile_form, reconcile_form(socket.assigns.memories, memory))}
  end

  def handle_event("new_memory", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected, nil)
     |> assign(:selected_hx_ingest_runs, [])
     |> assign(:edges, [])
     |> assign_form(:memory_form, memory_form(nil), :memory)
     |> assign_form(:edge_form, edge_form(nil), :edge)
     |> assign(:reconcile_form, reconcile_form(socket.assigns.memories, nil))}
  end

  def handle_event("delete_memory", %{"id" => id}, socket) do
    deleted = Memory.delete_memory!(id)
    if agent = Runtime.get_agent!(deleted.agent_id), do: Memory.sync_markdown(agent)

    {memories, memory_rankings} = load_memories(socket.assigns.filters)

    selected =
      socket.assigns.selected && maybe_refresh_selection(memories, socket.assigns.selected.id)

    selected = selected || List.first(memories)

    {:noreply,
     socket
     |> put_flash(:info, "Memory deleted")
     |> assign(:memories, memories)
     |> assign(:memory_rankings, memory_rankings)
     |> assign(:selected, selected)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
     |> assign(:edges, load_edges(selected))
     |> assign(:stats, stats())
     |> assign_form(:memory_form, memory_form(selected), :memory)
     |> assign_form(:edge_form, edge_form(selected), :edge)
     |> assign(:reconcile_form, reconcile_form(memories, selected))}
  end

  def handle_event("save_memory", %{"memory" => params}, socket) do
    result =
      case socket.assigns.selected do
        %Entry{} = entry -> Memory.update_memory(entry, normalize_memory_params(params))
        nil -> Memory.create_memory(normalize_memory_params(params))
      end

    case result do
      {:ok, memory} ->
        if agent = Runtime.get_agent!(memory.agent_id), do: Memory.sync_markdown(agent)
        {memories, memory_rankings} = load_memories(socket.assigns.filters)
        selected = Memory.get_memory!(memory.id)

        {:noreply,
         socket
         |> put_flash(:info, "Memory saved")
         |> assign(:memories, memories)
         |> assign(:memory_rankings, memory_rankings)
         |> assign(:selected, selected)
         |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
         |> assign(:edges, load_edges(selected))
         |> assign(:stats, stats())
         |> assign_form(:memory_form, memory_form(selected), :memory)
         |> assign_form(:edge_form, edge_form(selected), :edge)
         |> assign(:reconcile_form, reconcile_form(memories, selected))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :memory_form, changeset, :memory)}
    end
  end

  def handle_event("link_memory", %{"edge" => _params}, %{assigns: %{selected: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Select a memory before linking it.")}
  end

  def handle_event("link_memory", %{"edge" => params}, socket) do
    params = normalize_edge_params(socket.assigns.selected, params)

    case Memory.link_memories(params) do
      {:ok, _edge} ->
        {:noreply,
         socket
         |> put_flash(:info, "Memory link saved")
         |> assign(:edges, load_edges(socket.assigns.selected))
         |> assign_form(:edge_form, edge_form(socket.assigns.selected), :edge)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :edge_form, changeset, :edge)}
    end
  end

  def handle_event("delete_edge", %{"id" => id}, socket) do
    Memory.delete_edge!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Memory link deleted")
     |> assign(:edges, load_edges(socket.assigns.selected))}
  end

  def handle_event(
        "reconcile_memory",
        %{"reconcile" => _params},
        %{assigns: %{selected: nil}} = socket
      ) do
    {:noreply, put_flash(socket, :error, "Select a memory before reconciling it.")}
  end

  def handle_event("reconcile_memory", %{"reconcile" => params}, socket) do
    mode = params["mode"] |> to_string()
    source = socket.assigns.selected
    target_id = parse_integer(params["target_id"])
    content = blank_to_nil(params["content"])

    result =
      case {mode, target_id} do
        {mode, nil} when mode in ["merge", "supersede", "conflict", "resolve_conflict"] ->
          {:error, :missing_target}

        {"merge", target_id} ->
          Memory.reconcile_memory!(source.id, target_id, :merge,
            content: content || source.content
          )

        {"supersede", target_id} ->
          Memory.reconcile_memory!(source.id, target_id, :supersede)

        {"conflict", target_id} ->
          Memory.conflict_memory!(source.id, target_id, reason: content)

        {"resolve_conflict", target_id} ->
          Memory.resolve_conflict!(source.id, target_id,
            content: content || source.content,
            note: content
          )

        _ ->
          {:error, :invalid_mode}
      end

    case result do
      {:ok, reconciled} ->
        selected_memory = Map.get(reconciled, :target) || Map.get(reconciled, :winner)

        if agent = Runtime.get_agent!(selected_memory.agent_id), do: Memory.sync_markdown(agent)

        filters =
          refresh_filters_after_reconcile(socket.assigns.filters, selected_memory.status)

        {memories, memory_rankings} = load_memories(filters)
        selected = Memory.get_memory!(selected_memory.id)

        {:noreply,
         socket
         |> put_flash(:info, "Memory reconciled")
         |> assign(:filters, filters)
         |> assign(:filter_form, to_form(filters, as: :filters))
         |> assign(:memories, memories)
         |> assign(:memory_rankings, memory_rankings)
         |> assign(:selected, selected)
         |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
         |> assign(:edges, load_edges(selected))
         |> assign(:stats, stats())
         |> assign_form(:memory_form, memory_form(selected), :memory)
         |> assign_form(:edge_form, edge_form(selected), :edge)
         |> assign(:reconcile_form, reconcile_form(memories, selected))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Memory reconciliation failed: #{inspect(reason)}")}
    end
  rescue
    error ->
      {:noreply,
       put_flash(socket, :error, "Memory reconciliation failed: #{Exception.message(error)}")}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = safe_page_number(page)
    {memories, memory_rankings, has_next} = load_memories_paginated(socket.assigns.filters, page)

    selected =
      if socket.assigns.selected do
        maybe_refresh_selection(memories, socket.assigns.selected.id)
      end

    selected = selected || List.first(memories)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:has_next, has_next)
     |> assign(:memories, memories)
     |> assign(:memory_rankings, memory_rankings)
     |> assign(:selected, selected)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
     |> assign(:edges, load_edges(selected))
     |> assign_form(:memory_form, memory_form(selected), :memory)
     |> assign_form(:edge_form, edge_form(selected), :edge)
     |> assign(:reconcile_form, reconcile_form(memories, selected))}
  end

  @impl true
  def handle_info({:memory_updated, _agent_id}, socket) do
    {memories, memory_rankings} = load_memories(socket.assigns.filters)

    selected =
      if socket.assigns.selected do
        maybe_refresh_selection(memories, socket.assigns.selected.id)
      end

    {:noreply,
     socket
     |> assign(:memories, memories)
     |> assign(:memory_rankings, memory_rankings)
     |> assign(:embedding_status, current_embedding_status(socket.assigns.filters))
     |> assign(:ingested_files, load_ingested_files(socket.assigns.filters))
     |> assign(:hx_ingest_runs, load_hx_ingest_runs(socket.assigns.filters))
     |> assign(:selected, selected)
     |> assign(:selected_hx_ingest_runs, selected_hx_ingest_runs(selected))
     |> assign(:edges, load_edges(selected))
     |> assign(:stats, stats())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[0.9fr_1.1fr]">
        <article class="glass-panel p-6">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
                Typed graph memory
              </div>
              <h2 class="mt-3 font-display text-4xl">Authoritative memory store</h2>
            </div>
            <div class="flex gap-3">
              <button
                phx-click="new_memory"
                class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                New memory
              </button>
              <button
                phx-click="sync"
                class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Sync markdown view
              </button>
            </div>
          </div>

          <div class="mt-6 rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Embedding posture
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  backend {@embedding_status.active_backend} · model {@embedding_status.active_model}
                </div>
              </div>
              <div class="text-right text-xs text-[var(--hx-mute)]">
                configured {@embedding_status.configured_backend}
              </div>
            </div>
            <div class="mt-4 grid gap-3 md:grid-cols-4">
              <div class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                <div class="font-mono text-[11px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Embedded
                </div>
                <div class="mt-2 font-display text-2xl text-white">
                  {@embedding_status.embedded_count}
                </div>
              </div>
              <div class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                <div class="font-mono text-[11px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Missing
                </div>
                <div class="mt-2 font-display text-2xl text-white">
                  {@embedding_status.unembedded_count}
                </div>
              </div>
              <div class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                <div class="font-mono text-[11px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Stale
                </div>
                <div class="mt-2 font-display text-2xl text-white">
                  {@embedding_status.stale_count}
                </div>
              </div>
              <div class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                <div class="font-mono text-[11px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Fallback writes
                </div>
                <div class="mt-2 font-display text-2xl text-white">
                  {@embedding_status.fallback_count}
                </div>
              </div>
            </div>
            <p :if={@embedding_status.degraded?} class="mt-3 text-xs text-amber-200">
              The configured embedding backend is degraded; new writes are falling back to the active local backend.
            </p>
          </div>

          <div class="mt-6 rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Ingest queue
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  {if @ingest_agent,
                    do: "Agent #{@ingest_agent.name} · #{@ingest_agent.workspace_root}/ingest",
                    else: "No agent selected"}
                </div>
              </div>
            </div>
            <div class="mt-4 grid gap-3 lg:grid-cols-2">
              <.form for={@ingest_form} phx-submit="ingest_file" class="grid gap-3">
                <.input field={@ingest_form[:filename]} label="Import filename from ingest/" />
                <.input
                  field={@ingest_form[:force]}
                  type="checkbox"
                  label="Force reingest even if unchanged"
                />
                <div class="pt-1">
                  <.button>Run ingest</.button>
                </div>
              </.form>
              <.form for={@archive_ingest_form} phx-submit="archive_ingest_file" class="grid gap-3">
                <.input field={@archive_ingest_form[:filename]} label="Archive ingest file" />
                <div class="pt-1">
                  <.button>Archive file memories</.button>
                </div>
              </.form>
            </div>
            <div class="mt-4 space-y-2">
              <p
                :if={@ingested_files == []}
                class="text-sm text-[var(--hx-mute)]"
              >
                No active ingest-backed files for the selected agent.
              </p>
              <div
                :for={file <- @ingested_files}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">{file.file}</div>
                  <div class="text-xs text-[var(--hx-mute)]">{file.entries} entries</div>
                </div>
              </div>
            </div>
            <div class="mt-6">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Recent ingest runs
              </div>
              <div class="mt-3 space-y-2">
                <p :if={@hx_ingest_runs == []} class="text-sm text-[var(--hx-mute)]">
                  No ingest history for the selected agent yet.
                </p>
                <div
                  :for={run <- @hx_ingest_runs}
                  class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                >
                  <div class="flex items-center justify-between gap-3">
                    <div class="text-sm text-[var(--hx-accent)]">{run.source_file}</div>
                    <div class="text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      {run.status}
                    </div>
                  </div>
                  <div class="mt-2 text-xs text-[var(--hx-mute)]">
                    created {run.created_count} - restored {ingest_run_restored_count(run)} - skipped {run.skipped_count} - archived {run.archived_count} - {format_datetime(
                      run.inserted_at
                    )}
                  </div>
                  <div
                    :if={
                      run.metadata["reason"] || run.metadata["document_hash"] ||
                        run.metadata["forced"]
                    }
                    class="mt-2 text-xs text-[var(--hx-mute)]"
                  >
                    <span :if={run.metadata["reason"]}>reason {run.metadata["reason"]}</span>
                    <span :if={run.metadata["document_hash"]}>
                      document {String.slice(run.metadata["document_hash"], 0, 12)}
                    </span>
                    <span :if={run.metadata["forced"]}>forced reingest</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <form phx-submit="search" class="mt-6 max-w-xl">
            <label class="input w-full border-white/10 bg-black/10">
              <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Query
              </span>
              <input
                type="text"
                name="q"
                value={@filters["query"]}
                placeholder="Recall preferences, decisions, goals..."
              />
            </label>
          </form>

          <.form
            for={@filter_form}
            phx-submit="filter_memories"
            class="mt-4 grid gap-3 md:grid-cols-3"
          >
            <.input field={@filter_form[:query]} label="Query" />
            <.input
              field={@filter_form[:agent_id]}
              type="select"
              label="Agent"
              options={[{"All agents", ""} | Enum.map(@agents, &{"#{&1.name} (#{&1.slug})", &1.id})]}
            />
            <.input
              field={@filter_form[:type]}
              type="select"
              label="Type"
              options={[{"All types", ""} | Enum.map(@memory_types, &{&1, &1})]}
            />
            <.input
              field={@filter_form[:status]}
              type="select"
              label="Status"
              options={Enum.map(@memory_statuses, &{format_status_option(&1), &1})}
            />
            <.input
              field={@filter_form[:min_importance]}
              type="number"
              label="Min importance"
              min="0"
              max="1"
              step="0.1"
            />
            <div class="md:col-span-3 pt-1">
              <.button>Filter memory</.button>
            </div>
          </.form>

          <div class="mt-6 grid gap-3">
            <div
              :for={memory <- @memories}
              class={[
                "rounded-2xl border px-4 py-4 text-left transition",
                if(@selected && @selected.id == memory.id,
                  do: "border-[var(--hx-accent)] bg-[rgba(245,110,66,0.08)]",
                  else: "border-white/10 bg-black/10 hover:bg-white/5"
                )
              ]}
            >
              <button
                type="button"
                phx-click="select_memory"
                phx-value-id={memory.id}
                class="w-full text-left"
              >
                <div class="flex items-center justify-between gap-4">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                      {memory.type}
                    </span>
                    <span class={[
                      "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                      status_badge_class(memory.status)
                    ]}>
                      {memory.status}
                    </span>
                  </div>
                  <span class="text-xs text-[var(--hx-mute)]">
                    importance {Float.round(memory.importance, 2)}
                    <span :if={ranked = memory_ranking(@memory_rankings, memory)}>
                      · score {Float.round(ranked.score, 3)}
                      <span :if={is_float(ranked[:vector_score])}>
                        · embedding {Float.round(ranked.vector_score, 3)}
                      </span>
                    </span>
                  </span>
                </div>
                <p class="mt-3 text-sm leading-6">{memory.content}</p>
                <div
                  :if={ranked = memory_ranking(@memory_rankings, memory)}
                  class="mt-3 flex flex-wrap gap-2 text-xs"
                >
                  <span
                    :for={reason <- ranked.reasons || []}
                    class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    {reason}
                  </span>
                  <span
                    :if={embedding_backend(memory)}
                    class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    embedding {embedding_backend(memory)}
                  </span>
                  <span
                    :for={label <- score_breakdown_labels(ranked)}
                    class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    {label}
                  </span>
                </div>
              </button>
              <div class="mt-4">
                <button
                  type="button"
                  phx-click="delete_memory"
                  phx-value-id={memory.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Delete
                </button>
              </div>
            </div>
            <div
              :if={@memories == []}
              class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
            >
              No memories match the current query.
            </div>
          </div>
          <.pagination page={@page} has_next={@has_next} />
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            {if @selected, do: "Edit memory", else: "Create memory"}
          </div>
          <.form for={@memory_form} phx-submit="save_memory" class="mt-6 space-y-2">
            <.input
              field={@memory_form[:agent_id]}
              type="select"
              label="Agent"
              options={Enum.map(@agents, &{"#{&1.name} (#{&1.slug})", &1.id})}
            />
            <.input
              field={@memory_form[:type]}
              type="select"
              label="Type"
              options={Enum.map(@memory_types, &{&1, &1})}
            />
            <.input
              field={@memory_form[:status]}
              type="select"
              label="Status"
              options={
                Enum.reject(@memory_statuses, &(&1 == "all"))
                |> Enum.map(&{format_status_option(&1), &1})
              }
            />
            <.input
              field={@memory_form[:importance]}
              type="number"
              label="Importance"
              min="0"
              max="1"
              step="0.1"
            />
            <.input field={@memory_form[:content]} type="textarea" label="Content" />
            <div class="pt-2">
              <.button>Save memory</.button>
            </div>
          </.form>

          <div :if={@selected} class="mt-8">
            <div class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
              <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
                Embedding profile
              </div>
              <dl class="mt-4 grid gap-3 text-sm text-[var(--hx-mute)] md:grid-cols-2">
                <div :for={{label, value} <- memory_embedding_profile(@selected)}>
                  <dt class="font-mono text-[11px] uppercase tracking-[0.18em]">{label}</dt>
                  <dd class="mt-1 break-all text-white">{value}</dd>
                </div>
              </dl>
            </div>

            <div
              :if={ingest_backed_memory?(@selected)}
              class="mt-6 rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
                Ingest provenance
              </div>
              <dl class="mt-4 grid gap-3 text-sm text-[var(--hx-mute)] md:grid-cols-2">
                <div :for={{label, value} <- memory_provenance(@selected)}>
                  <dt class="font-mono text-[11px] uppercase tracking-[0.18em]">{label}</dt>
                  <dd class="mt-1 break-all text-white">{value}</dd>
                </div>
              </dl>
              <div class="mt-5">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Recent runs for this source
                </div>
                <div class="mt-3 space-y-2">
                  <div
                    :for={run <- @selected_hx_ingest_runs}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                        {run.status}
                      </div>
                      <div class="text-xs text-[var(--hx-mute)]">
                        {format_datetime(run.inserted_at)}
                      </div>
                    </div>
                    <div class="mt-2 text-xs text-[var(--hx-mute)]">
                      created {run.created_count} - restored {ingest_run_restored_count(run)} - skipped {run.skipped_count} - archived {run.archived_count}
                    </div>
                  </div>
                  <p :if={@selected_hx_ingest_runs == []} class="text-sm text-[var(--hx-mute)]">
                    No recent ingest runs recorded for this source file.
                  </p>
                </div>
              </div>
            </div>

            <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
              Link selected memory
            </div>
            <.form for={@edge_form} phx-submit="link_memory" class="mt-4 space-y-2">
              <.input
                field={@edge_form[:to_memory_id]}
                type="select"
                label="Target memory"
                options={linkable_memory_options(@memories, @selected)}
              />
              <.input
                field={@edge_form[:kind]}
                type="select"
                label="Relationship"
                options={Enum.map(@edge_kinds, &{&1, &1})}
              />
              <.input
                field={@edge_form[:weight]}
                type="number"
                label="Weight"
                min="0.1"
                max="1"
                step="0.1"
              />
              <div class="pt-2">
                <.button>Save link</.button>
              </div>
            </.form>

            <div class="mt-8">
              <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
                Reconcile selected memory
              </div>
              <.form for={@reconcile_form} phx-submit="reconcile_memory" class="mt-4 space-y-2">
                <.input
                  field={@reconcile_form[:mode]}
                  type="select"
                  label="Mode"
                  options={[
                    {"Supersede into target", "supersede"},
                    {"Merge into target", "merge"},
                    {"Mark both memories as conflicted", "conflict"},
                    {"Resolve conflict in favor of selected memory", "resolve_conflict"}
                  ]}
                />
                <.input
                  field={@reconcile_form[:target_id]}
                  type="select"
                  label="Target memory"
                  options={reconcilable_memory_options(@memories, @selected)}
                />
                <.input
                  field={@reconcile_form[:content]}
                  type="textarea"
                  label="Merged content or reconciliation note"
                />
                <div class="pt-2">
                  <.button>Reconcile memory</.button>
                </div>
              </.form>
            </div>

            <div class="mt-6 space-y-3">
              <div
                :for={edge <- @edges}
                class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
              >
                <div class="flex items-center justify-between gap-4">
                  <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                    {edge.kind}
                  </span>
                  <span class="text-xs text-[var(--hx-mute)]">
                    weight {Float.round(edge.weight, 2)}
                  </span>
                </div>
                <p class="mt-3 text-sm text-[var(--hx-mute)]">
                  {edge_label(edge, @selected)}
                </p>
                <div class="mt-4">
                  <button
                    type="button"
                    phx-click="delete_edge"
                    phx-value-id={edge.id}
                    class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Delete link
                  </button>
                </div>
              </div>
              <div
                :if={@edges == []}
                class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
              >
                No links for this memory yet.
              </div>
            </div>
          </div>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  @memory_page_size 50

  defp load_memories(filters) do
    opts = [
      limit: @memory_page_size,
      agent_id: parse_integer(filters["agent_id"]),
      type: blank_to_nil(filters["type"]),
      status: blank_to_nil(filters["status"]) || "active",
      min_importance: parse_float(filters["min_importance"], nil)
    ]

    case blank_to_nil(filters["query"]) do
      nil ->
        memories =
          Memory.search(
            parse_integer(filters["agent_id"]),
            filters["query"],
            @memory_page_size,
            opts
          )

        {memories, %{}}

      query ->
        ranked =
          Memory.search_ranked(
            parse_integer(filters["agent_id"]),
            query,
            @memory_page_size,
            opts
          )

        {Enum.map(ranked, & &1.entry), map_rankings(ranked)}
    end
  end

  defp load_memories_paginated(filters, page) do
    offset = (page - 1) * @memory_page_size

    opts = [
      limit: @memory_page_size + 1,
      offset: offset,
      agent_id: parse_integer(filters["agent_id"]),
      type: blank_to_nil(filters["type"]),
      status: blank_to_nil(filters["status"]) || "active",
      min_importance: parse_float(filters["min_importance"], nil)
    ]

    case blank_to_nil(filters["query"]) do
      nil ->
        results =
          Memory.search(
            parse_integer(filters["agent_id"]),
            filters["query"],
            @memory_page_size + 1,
            opts
          )

        {Enum.take(results, @memory_page_size), %{}, length(results) > @memory_page_size}

      query ->
        ranked =
          Memory.search_ranked(
            parse_integer(filters["agent_id"]),
            query,
            offset + @memory_page_size + 1,
            opts
          )

        page_ranked = ranked |> Enum.drop(offset) |> Enum.take(@memory_page_size + 1)
        has_next = length(page_ranked) > @memory_page_size
        page_ranked = Enum.take(page_ranked, @memory_page_size)

        {Enum.map(page_ranked, & &1.entry), map_rankings(page_ranked), has_next}
    end
  end

  defp load_ingested_files(filters) do
    case current_ingest_agent(filters) do
      nil -> []
      agent -> Runtime.list_ingested_files(agent.id)
    end
  end

  defp current_embedding_status(filters) do
    Memory.embedding_status(parse_integer(filters["agent_id"]))
  end

  defp load_hx_ingest_runs(filters) do
    case current_ingest_agent(filters) do
      nil -> []
      agent -> Runtime.list_ingest_runs(agent.id, 10)
    end
  end

  defp selected_hx_ingest_runs(nil), do: []

  defp selected_hx_ingest_runs(memory) do
    source_file = get_in(memory.metadata || %{}, ["source_file"])

    with true <- ingest_backed_memory?(memory),
         source_file when is_binary(source_file) <- source_file do
      Runtime.list_ingest_runs(memory.agent_id, 8)
      |> Enum.filter(&(&1.source_file == source_file))
    else
      _ -> []
    end
  end

  defp current_ingest_agent(filters) do
    case parse_integer(filters["agent_id"]) do
      nil -> Runtime.get_default_agent()
      agent_id -> Runtime.get_agent!(agent_id)
    end
  end

  defp memory_types, do: ~w(Fact Preference Decision Identity Event Observation Goal Todo)
  defp memory_statuses, do: ~w(active conflicted superseded merged archived all)
  defp edge_kinds, do: ~w(relates_to contradicts supersedes supports part_of)

  defp load_edges(nil), do: []
  defp load_edges(memory), do: Memory.list_edges_for(memory.id)

  defp memory_form(nil) do
    agent_id = Runtime.get_default_agent() |> then(&(&1 && &1.id))

    Memory.change_memory(%Entry{}, %{
      agent_id: agent_id,
      type: "Fact",
      status: "active",
      importance: 0.7,
      content: ""
    })
  end

  defp memory_form(memory), do: Memory.change_memory(memory)

  defp edge_form(nil) do
    Memory.change_edge(%Edge{}, %{kind: "relates_to", weight: 1.0})
  end

  defp edge_form(memory) do
    Memory.change_edge(%Edge{}, %{from_memory_id: memory.id, kind: "relates_to", weight: 1.0})
  end

  defp assign_form(socket, key, changeset, as) do
    assign(socket, key, to_form(changeset, as: as))
  end

  defp normalize_memory_params(params) do
    params
    |> Map.put("importance", parse_float(params["importance"], 0.7))
    |> Map.put("last_seen_at", DateTime.utc_now())
  end

  defp normalize_edge_params(selected, params) do
    params
    |> Map.put("from_memory_id", selected.id)
    |> Map.put("weight", parse_float(params["weight"], 1.0))
  end

  defp maybe_refresh_selection(memories, id) do
    Enum.find(memories, &(&1.id == id))
  end

  defp linkable_memory_options(memories, selected) do
    memories
    |> Enum.reject(&(&1.id == selected.id || &1.status != "active"))
    |> Enum.map(&{"#{&1.type}: #{truncate(&1.content, 52)}", &1.id})
  end

  defp reconcilable_memory_options(memories, selected) do
    memories
    |> Enum.reject(&(&1.id == selected.id || &1.status not in ["active", "conflicted"]))
    |> Enum.map(&{"#{&1.type} [#{&1.status}]: #{truncate(&1.content, 52)}", &1.id})
  end

  defp reconcile_form(_memories, nil) do
    to_form(%{"mode" => "supersede", "target_id" => "", "content" => ""}, as: :reconcile)
  end

  defp reconcile_form(memories, selected) do
    default_target =
      memories
      |> Enum.reject(&(&1.id == selected.id || &1.status not in ["active", "conflicted"]))
      |> List.first()
      |> then(&if(&1, do: to_string(&1.id), else: ""))

    to_form(
      %{
        "mode" => "supersede",
        "target_id" => default_target,
        "content" => selected.content
      },
      as: :reconcile
    )
  end

  defp edge_label(edge, selected) do
    target =
      if edge.from_memory_id == selected.id do
        edge.to_memory
      else
        edge.from_memory
      end

    "#{target.type}: #{truncate(target.content, 80)}"
  end

  defp embedding_backend(memory) do
    get_in(memory.metadata || %{}, ["embedding_backend"])
  end

  defp memory_embedding_profile(nil), do: []

  defp memory_embedding_profile(memory) do
    metadata = memory.metadata || %{}

    vector =
      case memory.embedding do
        %Pgvector{} = value -> Pgvector.to_list(value)
        values when is_list(values) -> values
        _ -> []
      end

    [
      {"backend", metadata["embedding_backend"] || "none"},
      {"model", metadata["embedding_model"] || "none"},
      {"dimensions", to_string(metadata["embedding_dimensions"] || length(vector))},
      {"generated", format_embedding_generated_at(metadata["embedding_generated_at"])},
      {"stored values", to_string(length(vector))}
    ]
  end

  defp format_embedding_generated_at(nil), do: "never"

  defp format_embedding_generated_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> format_datetime(parsed)
      _ -> value
    end
  end

  defp format_embedding_generated_at(value), do: format_datetime(value)

  defp refresh_filters_after_reconcile(filters, "conflicted") do
    case blank_to_nil(filters["status"]) do
      nil -> Map.put(filters, "status", "conflicted")
      "active" -> Map.put(filters, "status", "conflicted")
      _ -> filters
    end
  end

  defp refresh_filters_after_reconcile(filters, "active") do
    case blank_to_nil(filters["status"]) do
      "conflicted" -> Map.put(filters, "status", "active")
      _ -> filters
    end
  end

  defp refresh_filters_after_reconcile(filters, _status), do: filters

  defp truncate(content, limit) when byte_size(content) <= limit, do: content
  defp truncate(content, limit), do: String.slice(content, 0, limit) <> "..."

  defp parse_float(nil, default), do: default
  defp parse_float("", default), do: default
  defp parse_float(value, _default) when is_float(value), do: value

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> parsed
      :error -> default
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp truthy?(value), do: value in [true, "true", "on", "1"]

  defp ingest_message(filename, %{unchanged: true, skipped: skipped}) do
    "Ingest skipped for #{filename}: unchanged document (#{skipped} chunks matched the last import)"
  end

  defp ingest_message(filename, result) do
    "Ingested #{filename}: #{result.created} created, #{Map.get(result, :restored, 0)} restored, #{result.skipped} skipped, #{result.archived} archived"
  end

  defp ingest_backed_memory?(nil), do: false
  defp ingest_backed_memory?(memory), do: get_in(memory.metadata || %{}, ["source"]) == "ingest"

  defp memory_provenance(memory) do
    metadata = memory.metadata || %{}

    [
      {"Source file", metadata["source_file"] || "unknown"},
      {"Source path", metadata["source_path"] || "unknown"},
      {"Section", metadata["section"] || "n/a"},
      {"Section index", stringify_provenance(metadata["section_index"])},
      {"Content hash", metadata["content_hash"] || "unknown"},
      {"Document hash", metadata["document_hash"] || "unknown"}
    ]
  end

  defp ingest_run_restored_count(run), do: get_in(run.metadata || %{}, ["restored_count"]) || 0

  defp stringify_provenance(nil), do: "n/a"
  defp stringify_provenance(value), do: to_string(value)

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp default_filters do
    %{"query" => "", "agent_id" => "", "type" => "", "status" => "active", "min_importance" => ""}
  end

  defp format_status_option("all"), do: "All statuses"
  defp format_status_option(status), do: status |> String.replace("_", " ") |> String.capitalize()

  defp safe_page_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp safe_page_number(value) when is_integer(value) and value > 0, do: value
  defp safe_page_number(_), do: 1

  defp status_badge_class("active"),
    do: "border-emerald-400/30 bg-emerald-400/10 text-emerald-200"

  defp status_badge_class("superseded"), do: "border-amber-400/30 bg-amber-400/10 text-amber-200"
  defp status_badge_class("merged"), do: "border-cyan-400/30 bg-cyan-400/10 text-cyan-200"
  defp status_badge_class(_), do: "border-white/10 bg-black/10 text-[var(--hx-mute)]"

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

  defp map_rankings(ranked) do
    Map.new(ranked, fn item -> {item.entry.id, item} end)
  end

  defp score_breakdown_labels(%{score_breakdown: breakdown}) when is_map(breakdown) do
    breakdown
    |> Enum.reject(fn {_key, value} -> value in [nil, 0.0] end)
    |> Enum.sort_by(fn {_key, value} -> -value end)
    |> Enum.take(3)
    |> Enum.map(fn {key, value} -> "#{key} #{Float.round(value, 3)}" end)
  end

  defp score_breakdown_labels(_ranked), do: []

  defp memory_ranking(rankings, memory), do: Map.get(rankings || %{}, memory.id)
end
