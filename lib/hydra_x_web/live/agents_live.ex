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

  def handle_event("approve_work_item", %{"id" => id, "action" => action}, socket) do
    work_item_id = String.to_integer(id)
    work_item = Runtime.get_work_item!(work_item_id)

    {_updated, _record} =
      Runtime.approve_work_item!(work_item_id, %{
        "requested_action" => action,
        "rationale" => "Approved from the /agents control plane."
      })

    {:noreply,
     socket
     |> put_flash(:info, "Approved #{work_item.kind} work item ##{work_item.id}")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("reject_work_item", %{"id" => id, "action" => action}, socket) do
    work_item_id = String.to_integer(id)
    work_item = Runtime.get_work_item!(work_item_id)

    {_updated, _record} =
      Runtime.reject_work_item!(work_item_id, %{
        "requested_action" => action,
        "rationale" => "Rejected from the /agents control plane."
      })

    {:noreply,
     socket
     |> put_flash(:info, "Rejected #{work_item.kind} work item ##{work_item.id}")
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

  def handle_event("save_compaction_policy", %{"compaction_policy" => params}, socket) do
    agent_id = params["agent_id"] |> String.to_integer()

    try do
      Runtime.save_compaction_policy!(agent_id, %{
        "soft" => params["soft"],
        "medium" => params["medium"],
        "hard" => params["hard"]
      })

      {:noreply,
       socket
       |> put_flash(:info, "Compaction policy updated")
       |> assign(:agents, agents_with_runtime())
       |> assign(:stats, stats())}
    rescue
      error ->
        {:noreply,
         put_flash(socket, :error, "Compaction policy failed: #{Exception.message(error)}")}
    end
  end

  def handle_event("save_agent_tool_policy", %{"agent_tool_policy" => params}, socket) do
    agent_id = params["agent_id"] |> String.to_integer()

    attrs =
      params
      |> Map.drop(["agent_id"])
      |> normalize_checkbox_fields([
        "workspace_list_enabled",
        "workspace_read_enabled",
        "workspace_write_enabled",
        "http_fetch_enabled",
        "browser_automation_enabled",
        "web_search_enabled",
        "shell_command_enabled"
      ])

    case Runtime.save_agent_tool_policy(agent_id, attrs) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent tool policy updated")
         |> assign(:agents, agents_with_runtime())
         |> assign(:stats, stats())}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Tool policy failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("reset_agent_tool_policy", %{"id" => id}, socket) do
    Runtime.delete_agent_tool_policy!(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(:info, "Agent tool policy override removed")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("save_agent_control_policy", %{"agent_control_policy" => params}, socket) do
    agent_id = params["agent_id"] |> String.to_integer()

    attrs =
      params
      |> Map.drop(["agent_id"])
      |> normalize_checkbox_fields(["require_recent_auth_for_sensitive_actions"])

    case Runtime.save_agent_control_policy(agent_id, attrs) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent control policy updated")
         |> assign(:agents, agents_with_runtime())
         |> assign(:stats, stats())}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Control policy failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("reset_agent_control_policy", %{"id" => id}, socket) do
    Runtime.delete_agent_control_policy!(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(:info, "Agent control policy override removed")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("save_provider_routing", %{"provider_routing" => params}, socket) do
    agent_id = String.to_integer(params["agent_id"])

    case Runtime.save_agent_provider_routing(agent_id, Map.drop(params, ["agent_id"])) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent provider routing updated")
         |> assign(:agents, agents_with_runtime())
         |> assign(:stats, stats())}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Provider routing failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("reset_provider_routing", %{"id" => id}, socket) do
    Runtime.clear_agent_provider_routing!(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(:info, "Agent provider routing reset")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("warm_provider_route", %{"id" => id}, socket) do
    {:ok, _agent, status} = Runtime.warm_agent_provider_routing(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Provider warmup #{status["status"]}#{if(status["selected_provider_name"], do: " via #{status["selected_provider_name"]}", else: "")}"
     )
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("refresh_skills", %{"id" => id}, socket) do
    {:ok, skills} = Runtime.refresh_agent_skills(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(:info, "Discovered #{length(skills)} skills")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("toggle_skill", %{"id" => id}, socket) do
    skill = Runtime.get_skill!(String.to_integer(id))

    if skill.enabled do
      Runtime.disable_skill!(skill.id)
    else
      Runtime.enable_skill!(skill.id)
    end

    {:noreply,
     socket
     |> put_flash(:info, "Skill #{if(skill.enabled, do: "disabled", else: "enabled")}")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("refresh_mcp", %{"id" => id}, socket) do
    agent_id = String.to_integer(id)
    {:ok, bindings} = Runtime.refresh_agent_mcp_servers(agent_id)
    _ = Runtime.list_agent_mcp_actions(agent_id, refresh: true)

    {:noreply,
     socket
     |> put_flash(:info, "Discovered #{length(bindings)} MCP integrations")
     |> assign(:agents, agents_with_runtime())
     |> assign(:stats, stats())}
  end

  def handle_event("toggle_agent_mcp", %{"id" => id}, socket) do
    binding = Runtime.get_agent_mcp_server!(String.to_integer(id))

    if binding.enabled do
      Runtime.disable_agent_mcp_server!(binding.id)
    else
      Runtime.enable_agent_mcp_server!(binding.id)
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "MCP integration #{if(binding.enabled, do: "disabled", else: "enabled")}"
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
                  <div class="mt-2 flex flex-wrap items-center gap-2">
                    <span class="rounded-full border border-fuchsia-400/20 bg-fuchsia-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-fuchsia-200">
                      {agent.role}
                    </span>
                    <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      {agent.capability_summary.max_autonomy_level}
                    </span>
                    <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      {length(agent.recent_work_items)} work items
                    </span>
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
              <div class="mt-2 text-xs text-[var(--hx-mute)]">
                readiness {agent.runtime.readiness} · warmup {agent.runtime.warmup_status} · selected {provider_name(
                  agent.provider_route.provider
                )}
              </div>
              <div :if={agent.runtime.last_warm_error} class="mt-1 text-xs text-amber-200/80">
                {agent.runtime.last_warm_error}
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Capability contract
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  tools {list_summary(agent.capability_summary.tools)} · artifacts {list_summary(
                    agent.capability_summary.artifact_types
                  )}
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  delivery {list_summary(agent.capability_summary.delivery_modes)} · side effects {list_summary(
                    agent.capability_summary.side_effect_classes
                  )}
                </div>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Recent work items
                </div>
                <div class="mt-2 grid gap-3 md:grid-cols-6">
                  <article class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Pending review
                    </div>
                    <div class="mt-2 font-display text-2xl">{agent.work_queue.pending_review}</div>
                  </article>
                  <article class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Awaiting operator
                    </div>
                    <div class="mt-2 font-display text-2xl">{agent.work_queue.awaiting_operator}</div>
                  </article>
                  <article class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Extensions gated
                    </div>
                    <div class="mt-2 font-display text-2xl">{agent.work_queue.extensions_gated}</div>
                  </article>
                  <article class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Blocked/failed
                    </div>
                    <div class="mt-2 font-display text-2xl">{agent.work_queue.blocked_or_failed}</div>
                  </article>
                  <article class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Role backlog
                    </div>
                    <div class="mt-2 font-display text-2xl">{agent.work_queue.role_backlog}</div>
                  </article>
                  <article class="rounded-xl border border-white/10 bg-black/10 px-3 py-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Queue posture
                    </div>
                    <div class="mt-2 font-display text-2xl">{agent.work_queue.capacity_posture}</div>
                  </article>
                </div>
                <div class="mt-3 space-y-1 text-[11px] text-[var(--hx-mute)]">
                  <p>
                    role queue {agent.role_queue_backlog[:queued_count] || 0} · workers{" "}
                    {agent.role_queue_backlog[:worker_count] || 0} · active claims{" "}
                    {agent.role_queue_backlog[:active_claimed_count] || 0} · stale claims{" "}
                    {agent.role_queue_backlog[:stale_claimed_count] || 0} · deferred{" "}
                    {agent.role_queue_backlog[:deferred_count] || 0} · urgent{" "}
                    {agent.role_queue_backlog[:required_role_queued_count] || 0}/ {agent.role_queue_backlog[
                      :required_role_deferred_count
                    ] || 0}
                  </p>
                  <p :if={(agent.work_queue[:orphaned_role_assignments] || 0) > 0}>
                    orphaned role {agent.work_queue[:orphaned_role_assignments]}
                  </p>
                  <p :if={detail = worker_pressure_detail(agent.worker_pressure)}>
                    {detail}
                  </p>
                  <p :if={detail = delegation_supervision_detail(agent.delegation_supervision)}>
                    {detail}
                  </p>
                  <p :if={dispatch = agent.recent_role_dispatch}>
                    {dispatch}
                  </p>
                  <p :if={recovery = agent.recent_assignment_recovery}>
                    {recovery}
                  </p>
                  <p :if={cleanup = agent.recent_stale_claim_cleanup}>
                    {cleanup}
                  </p>
                </div>
                <div class="mt-3 space-y-2">
                  <p
                    :if={agent.recent_work_items == []}
                    class="text-sm text-[var(--hx-mute)]"
                  >
                    No autonomy work has been assigned to this agent yet.
                  </p>
                  <div
                    :for={item <- agent.recent_work_items}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex flex-wrap items-center justify-between gap-3">
                      <div class="text-sm text-[var(--hx-accent)]">
                        {item.kind} · {item.status}
                      </div>
                      <div class="text-xs text-[var(--hx-mute)]">
                        {item.execution_mode} · {item.approval_stage}
                      </div>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">{item.goal}</p>
                    <div class="mt-2 text-xs text-[var(--hx-mute)]">
                      priority {item.priority} · {work_item_artifact_summary(item)} · level{" "}
                      {item.autonomy_level} · effect {work_item_side_effect_class(item)}<span :if={
                        summary = work_item_promoted_memory_summary(item)
                      }> · {summary}</span>
                      <span :if={summary = work_item_delegation_summary(item)}>
                        · {summary}
                      </span>
                      <span :if={summary = work_item_publish_summary(item)}>
                        · {summary}
                      </span>
                      <span :if={summary = work_item_recovery_summary(item)}>
                        · {summary}
                      </span>
                      <span :if={summary = work_item_assignment_summary(item)}>
                        · {summary}
                      </span>
                    </div>
                    <div :if={work_item_actionable?(item)} class="mt-3 flex flex-wrap gap-2">
                      <button
                        id={"approve-work-item-#{item.id}"}
                        phx-click="approve_work_item"
                        phx-value-id={item.id}
                        phx-value-action={work_item_primary_action(item)}
                        class="btn btn-sm btn-outline border-emerald-400/20 bg-emerald-400/10 text-emerald-200 hover:bg-emerald-400/20"
                      >
                        {work_item_primary_action_label(item)}
                      </button>
                      <button
                        id={"reject-work-item-#{item.id}"}
                        phx-click="reject_work_item"
                        phx-value-id={item.id}
                        phx-value-action={work_item_primary_action(item)}
                        class="btn btn-sm btn-outline border-amber-400/20 bg-amber-400/10 text-amber-200 hover:bg-amber-400/20"
                      >
                        Reject
                      </button>
                    </div>
                    <div class="mt-2 flex flex-wrap gap-2 text-[11px] text-[var(--hx-mute)]">
                      <span class="rounded-full border border-white/10 px-3 py-1">
                        latest approval {work_item_latest_approval(item)}
                      </span>
                      <span
                        :if={work_item_last_action(item)}
                        class="rounded-full border border-white/10 px-3 py-1"
                      >
                        action {work_item_last_action(item)}
                      </span>
                      <span
                        :if={work_item_enablement_status(item)}
                        class="rounded-full border border-amber-400/20 bg-amber-400/10 px-3 py-1 text-amber-200"
                      >
                        {work_item_enablement_status(item)}
                      </span>
                      <span class="rounded-full border border-white/10 px-3 py-1">
                        level {item.autonomy_level}
                      </span>
                      <span class="rounded-full border border-white/10 px-3 py-1">
                        effect {work_item_side_effect_class(item)}
                      </span>
                      <span
                        :if={summary = work_item_assignment_summary(item)}
                        class="rounded-full border border-violet-400/20 bg-violet-400/10 px-3 py-1 text-violet-200"
                      >
                        {summary}
                      </span>
                      <span
                        :if={label = work_item_policy_failure_label(item)}
                        class="rounded-full border border-rose-400/20 bg-rose-400/10 px-3 py-1 text-rose-200"
                      >
                        {label}
                      </span>
                      <span
                        :if={summary = work_item_delegation_summary(item)}
                        class="rounded-full border border-indigo-400/20 bg-indigo-400/10 px-3 py-1 text-indigo-200"
                      >
                        {summary}
                      </span>
                      <span
                        :if={summary = work_item_publish_summary(item)}
                        class="rounded-full border border-sky-400/20 bg-sky-400/10 px-3 py-1 text-sky-200"
                      >
                        {summary}
                      </span>
                      <span
                        :if={summary = work_item_recovery_summary(item)}
                        class="rounded-full border border-fuchsia-400/20 bg-fuchsia-400/10 px-3 py-1 text-fuchsia-200"
                      >
                        {summary}
                      </span>
                    </div>
                    <div
                      :if={delegation_detail_lines = work_item_delegation_detail_lines(item)}
                      class="mt-2 space-y-1 text-[11px] text-[var(--hx-mute)]"
                    >
                      <p :for={detail <- delegation_detail_lines}>{detail}</p>
                    </div>
                    <div
                      :if={recovery_detail_lines = work_item_recovery_detail_lines(item)}
                      class="mt-2 space-y-1 text-[11px] text-[var(--hx-mute)]"
                    >
                      <p :for={detail <- recovery_detail_lines}>{detail}</p>
                    </div>
                    <div
                      :if={publish_detail_lines = work_item_publish_detail_lines(item)}
                      class="mt-2 space-y-1 text-[11px] text-[var(--hx-mute)]"
                    >
                      <p :for={detail <- publish_detail_lines}>{detail}</p>
                    </div>
                    <div :if={work_item_artifact_types(item) != []} class="mt-2 flex flex-wrap gap-2">
                      <span
                        :for={type <- work_item_artifact_types(item)}
                        class="rounded-full border border-white/10 px-3 py-1 text-[11px] text-[var(--hx-mute)]"
                      >
                        {type}
                      </span>
                    </div>
                    <div
                      :if={work_item_promoted_memory_labels(item) != []}
                      class="mt-2 flex flex-wrap gap-2"
                    >
                      <span
                        :for={label <- work_item_promoted_memory_labels(item)}
                        class="rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-1 text-[11px] text-emerald-200"
                      >
                        {label}
                      </span>
                    </div>
                  </div>
                </div>
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
                <div :if={agent.bulletin.top_memories != []} class="mt-3 space-y-2">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Top bulletin memories
                  </div>
                  <div
                    :for={memory <- Enum.take(agent.bulletin.top_memories, 3)}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex flex-wrap items-center justify-between gap-3">
                      <div class="text-sm text-[var(--hx-accent)]">
                        {bulletin_memory_value(memory, :type)}
                      </div>
                      <div class="text-xs text-[var(--hx-mute)]">
                        score {Float.round(bulletin_memory_value(memory, :score) || 0.0, 2)}
                      </div>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">
                      {bulletin_memory_value(memory, :content)}
                    </p>
                    <div class="mt-2 flex flex-wrap gap-2 text-[11px] text-[var(--hx-mute)]">
                      <span
                        :for={label <- bulletin_memory_labels(memory)}
                        class="rounded-full border border-white/10 px-3 py-1"
                      >
                        {label}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Compaction policy
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  Soft {agent.compaction_policy.soft} · Medium {agent.compaction_policy.medium} · Hard {agent.compaction_policy.hard}
                </div>
                <% policy_form =
                  to_form(compaction_policy_form(agent),
                    as: :compaction_policy,
                    id: "compaction-policy-#{agent.id}"
                  ) %>
                <.form
                  for={policy_form}
                  phx-submit="save_compaction_policy"
                  class="mt-4 grid gap-3 md:grid-cols-3"
                >
                  <input type="hidden" name="compaction_policy[agent_id]" value={agent.id} />
                  <.input field={policy_form[:soft]} type="number" label="Soft" min="1" />
                  <.input field={policy_form[:medium]} type="number" label="Medium" min="2" />
                  <.input field={policy_form[:hard]} type="number" label="Hard" min="3" />
                  <div class="md:col-span-3 pt-1">
                    <.button>Save compaction policy</.button>
                  </div>
                </.form>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="flex items-center justify-between gap-3">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Provider routing
                  </div>
                  <span class="text-xs text-[var(--hx-mute)]">
                    {agent.provider_route.source}
                  </span>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  default {provider_name(agent.provider_route.provider)} · fallbacks {fallback_summary(
                    agent.provider_route.fallbacks
                  )}
                </div>
                <% routing_form =
                  to_form(provider_routing_form(agent),
                    as: :provider_routing,
                    id: "provider-routing-#{agent.id}"
                  ) %>
                <.form
                  for={routing_form}
                  phx-submit="save_provider_routing"
                  class="mt-4 grid gap-3 md:grid-cols-2"
                >
                  <input type="hidden" name="provider_routing[agent_id]" value={agent.id} />
                  <.input
                    field={routing_form[:default_provider_id]}
                    type="select"
                    label="Agent default provider"
                    options={provider_options()}
                  />
                  <.input
                    field={routing_form[:fallback_provider_ids_csv]}
                    label="Fallback provider ids (comma separated)"
                  />
                  <.input
                    field={routing_form[:channel_provider_id]}
                    type="select"
                    label="Channel provider override"
                    options={provider_options()}
                  />
                  <.input
                    field={routing_form[:scheduler_provider_id]}
                    type="select"
                    label="Scheduler provider override"
                    options={provider_options()}
                  />
                  <.input
                    field={routing_form[:cortex_provider_id]}
                    type="select"
                    label="Cortex provider override"
                    options={provider_options()}
                  />
                  <.input
                    field={routing_form[:compactor_provider_id]}
                    type="select"
                    label="Compactor provider override"
                    options={provider_options()}
                  />
                  <div class="md:col-span-2 pt-1">
                    <.button>Save provider routing</.button>
                    <button
                      type="button"
                      phx-click="warm_provider_route"
                      phx-value-id={agent.id}
                      class="ml-3 inline-flex items-center rounded-2xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.18em] text-white transition hover:bg-white/10"
                    >
                      Warm route
                    </button>
                    <button
                      type="button"
                      phx-click="reset_provider_routing"
                      phx-value-id={agent.id}
                      class="ml-3 inline-flex items-center rounded-2xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.18em] text-white transition hover:bg-white/10"
                    >
                      Reset route
                    </button>
                  </div>
                </.form>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="flex items-center justify-between gap-3">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Effective policy
                  </div>
                  <span class="text-xs text-[var(--hx-mute)]">
                    {agent.effective_policy.routing.source}
                  </span>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  auth {if agent.effective_policy.auth.recent_auth_required,
                    do: "required",
                    else: "optional"} within {agent.effective_policy.auth.recent_auth_window_minutes}m
                  · route {agent.effective_policy.routing.provider_name}
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  interactive {channel_summary(agent.effective_policy.deliveries.interactive_channels)} ·
                  jobs {channel_summary(agent.effective_policy.deliveries.job_channels)} ·
                  ingest {channel_summary(agent.effective_policy.ingest.roots)}
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  {effective_tool_summary(agent.effective_policy)}
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  fallbacks {channel_summary(agent.effective_policy.routing.fallback_names)} ·
                  budget {policy_budget_summary(agent.effective_policy)} ·
                  workload {policy_workload_summary(agent.effective_policy)}
                </div>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="flex items-center justify-between gap-3">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Tool policy override
                  </div>
                  <span class="text-xs text-[var(--hx-mute)]">
                    {if agent.tool_policy_override, do: "override active", else: "inherits global"}
                  </span>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  list {enabled_label(agent.effective_tool_policy.workspace_list_enabled)} · read {enabled_label(
                    agent.effective_tool_policy.workspace_read_enabled
                  )} · write {enabled_label(agent.effective_tool_policy.workspace_write_enabled)} · browser {enabled_label(
                    agent.effective_tool_policy.browser_automation_enabled
                  )} · search {enabled_label(agent.effective_tool_policy.web_search_enabled)} · http {enabled_label(
                    agent.effective_tool_policy.http_fetch_enabled
                  )} · shell {enabled_label(agent.effective_tool_policy.shell_command_enabled)}
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  write via {channel_summary(agent.effective_tool_policy.workspace_write_channels)} ·
                  http via {channel_summary(agent.effective_tool_policy.http_fetch_channels)} ·
                  browser via {channel_summary(
                    agent.effective_tool_policy.browser_automation_channels
                  )} ·
                  search via {channel_summary(agent.effective_tool_policy.web_search_channels)} ·
                  shell via {channel_summary(agent.effective_tool_policy.shell_command_channels)}
                </div>
                <% tool_policy_form =
                  to_form(agent_tool_policy_form(agent),
                    as: :agent_tool_policy,
                    id: "agent-tool-policy-#{agent.id}"
                  ) %>
                <.form
                  for={tool_policy_form}
                  phx-submit="save_agent_tool_policy"
                  class="mt-4 grid gap-3 md:grid-cols-2"
                >
                  <input type="hidden" name="agent_tool_policy[agent_id]" value={agent.id} />
                  <.input
                    field={tool_policy_form[:workspace_list_enabled]}
                    type="checkbox"
                    label="Workspace list"
                  />
                  <.input
                    field={tool_policy_form[:workspace_read_enabled]}
                    type="checkbox"
                    label="Workspace read"
                  />
                  <.input
                    field={tool_policy_form[:workspace_write_enabled]}
                    type="checkbox"
                    label="Workspace write/patch"
                  />
                  <.input
                    field={tool_policy_form[:web_search_enabled]}
                    type="checkbox"
                    label="Web search"
                  />
                  <.input
                    field={tool_policy_form[:http_fetch_enabled]}
                    type="checkbox"
                    label="HTTP fetch"
                  />
                  <.input
                    field={tool_policy_form[:browser_automation_enabled]}
                    type="checkbox"
                    label="Browser automation"
                  />
                  <.input
                    field={tool_policy_form[:shell_command_enabled]}
                    type="checkbox"
                    label="Shell commands"
                  />
                  <.input
                    field={tool_policy_form[:shell_allowlist_csv]}
                    label="Shell allowlist (comma separated)"
                  />
                  <.input
                    field={tool_policy_form[:http_allowlist_csv]}
                    label="HTTP allowlist (comma separated)"
                  />
                  <.input
                    field={tool_policy_form[:workspace_write_channels_csv]}
                    label="Workspace write channels"
                  />
                  <.input
                    field={tool_policy_form[:http_fetch_channels_csv]}
                    label="HTTP fetch channels"
                  />
                  <.input
                    field={tool_policy_form[:browser_automation_channels_csv]}
                    label="Browser channels"
                  />
                  <.input
                    field={tool_policy_form[:web_search_channels_csv]}
                    label="Web search channels"
                  />
                  <.input
                    field={tool_policy_form[:shell_command_channels_csv]}
                    label="Shell channels"
                  />
                  <div class="md:col-span-2 pt-1">
                    <.button>Save tool override</.button>
                    <button
                      :if={agent.tool_policy_override}
                      type="button"
                      phx-click="reset_agent_tool_policy"
                      phx-value-id={agent.id}
                      class="ml-3 inline-flex items-center rounded-2xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.18em] text-white transition hover:bg-white/10"
                    >
                      Reset override
                    </button>
                  </div>
                </.form>
                <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                  <div class="flex items-center justify-between gap-3">
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Control policy override
                    </div>
                    <span class="text-xs text-[var(--hx-mute)]">
                      {if agent.control_policy_override,
                        do: "override active",
                        else: "inherits global"}
                    </span>
                  </div>
                  <div class="mt-2 text-sm text-[var(--hx-mute)]">
                    recent auth {if agent.effective_control_policy.require_recent_auth_for_sensitive_actions,
                      do: "required",
                      else: "optional"} within {agent.effective_control_policy.recent_auth_window_minutes}m
                  </div>
                  <div class="mt-2 text-xs text-[var(--hx-mute)]">
                    interactive delivery via {channel_summary(
                      agent.effective_control_policy.interactive_delivery_channels
                    )} ·
                    job delivery via {channel_summary(
                      agent.effective_control_policy.job_delivery_channels
                    )} ·
                    ingest roots {channel_summary(agent.effective_control_policy.ingest_roots)}
                  </div>
                  <% control_policy_form =
                    to_form(agent_control_policy_form(agent),
                      as: :agent_control_policy,
                      id: "agent-control-policy-#{agent.id}"
                    ) %>
                  <.form
                    for={control_policy_form}
                    phx-submit="save_agent_control_policy"
                    class="mt-4 grid gap-3 md:grid-cols-2"
                  >
                    <input type="hidden" name="agent_control_policy[agent_id]" value={agent.id} />
                    <.input
                      field={control_policy_form[:require_recent_auth_for_sensitive_actions]}
                      type="checkbox"
                      label="Require recent auth"
                    />
                    <.input
                      field={control_policy_form[:recent_auth_window_minutes]}
                      type="number"
                      label="Recent-auth window (minutes)"
                    />
                    <.input
                      field={control_policy_form[:interactive_delivery_channels_csv]}
                      label="Interactive delivery channels"
                    />
                    <.input
                      field={control_policy_form[:job_delivery_channels_csv]}
                      label="Job delivery channels"
                    />
                    <.input
                      field={control_policy_form[:ingest_roots_csv]}
                      label="Allowed ingest roots"
                    />
                    <div class="md:col-span-2 pt-1">
                      <.button>Save control override</.button>
                      <button
                        :if={agent.control_policy_override}
                        type="button"
                        phx-click="reset_agent_control_policy"
                        phx-value-id={agent.id}
                        class="ml-3 inline-flex items-center rounded-2xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.18em] text-white transition hover:bg-white/10"
                      >
                        Reset override
                      </button>
                    </div>
                  </.form>
                </div>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="flex items-center justify-between gap-3">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Skills
                  </div>
                  <button
                    type="button"
                    phx-click="refresh_skills"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Refresh skills
                  </button>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  {length(agent.skills)} discovered · {Enum.count(agent.skills, & &1.enabled)} enabled
                </div>
                <div class="mt-3 space-y-3">
                  <div
                    :for={skill <- agent.skills}
                    class="rounded-2xl border border-white/10 bg-black/10 px-4 py-3"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="text-sm font-semibold text-white">{skill.name}</div>
                        <div class="mt-1 font-mono text-[11px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                          {skill.slug}
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="toggle_skill"
                        phx-value-id={skill.id}
                        class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                      >
                        {if skill.enabled, do: "Disable", else: "Enable"}
                      </button>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">
                      {skill.description || "No description provided."}
                    </p>
                    <p :if={skill_tags(skill) != []} class="mt-2 text-xs text-[var(--hx-mute)]">
                      tags: {Enum.join(skill_tags(skill), ", ")}
                    </p>
                    <p :if={skill_tools(skill) != []} class="mt-1 text-xs text-[var(--hx-mute)]">
                      tools: {Enum.join(skill_tools(skill), ", ")}
                    </p>
                    <p
                      :if={skill_channels(skill) != []}
                      class="mt-1 text-xs text-[var(--hx-mute)]"
                    >
                      channels: {Enum.join(skill_channels(skill), ", ")}
                    </p>
                    <p
                      :if={skill_requires(skill) != []}
                      class="mt-1 text-xs text-[var(--hx-mute)]"
                    >
                      requires: {Enum.join(skill_requires(skill), ", ")}
                    </p>
                    <p
                      :if={skill_validation_errors(skill) != []}
                      class="mt-1 text-xs text-amber-200"
                    >
                      validation: {Enum.join(skill_validation_errors(skill), "; ")}
                    </p>
                    <div class="mt-2 text-xs text-[var(--hx-mute)]">
                      {if skill.enabled, do: "enabled", else: "disabled"} · {if skill_manifest_valid?(
                                                                                  skill
                                                                                ),
                                                                                do: "manifest valid",
                                                                                else:
                                                                                  "manifest invalid"} · {skill_version(
                        skill
                      ) ||
                        "unversioned"} · {get_in(
                        skill.metadata || %{},
                        ["relative_path"]
                      ) || skill.path}
                    </div>
                  </div>
                  <p :if={agent.skills == []} class="text-sm text-[var(--hx-mute)]">
                    No workspace skills discovered yet.
                  </p>
                </div>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="flex items-center justify-between gap-3">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    MCP integrations
                  </div>
                  <button
                    type="button"
                    phx-click="refresh_mcp"
                    phx-value-id={agent.id}
                    class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                  >
                    Refresh MCP
                  </button>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  {length(agent.mcp_servers)} discovered · {Enum.count(
                    agent.mcp_servers,
                    & &1.enabled
                  )} enabled
                </div>
                <div class="mt-3 space-y-3">
                  <div
                    :for={binding <- agent.mcp_servers}
                    class="rounded-2xl border border-white/10 bg-black/10 px-4 py-3"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="text-sm font-semibold text-white">
                          {binding.mcp_server_config.name}
                        </div>
                        <div class="mt-1 font-mono text-[11px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                          {binding.mcp_server_config.transport}
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="toggle_agent_mcp"
                        phx-value-id={binding.id}
                        class="btn btn-sm btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                      >
                        {if binding.enabled, do: "Disable", else: "Enable"}
                      </button>
                    </div>
                    <div class="mt-2 text-sm text-[var(--hx-mute)]">
                      {mcp_descriptor(binding.mcp_server_config)}
                    </div>
                    <p :if={mcp_actions(binding) != []} class="mt-2 text-xs text-[var(--hx-mute)]">
                      actions: {Enum.join(mcp_actions(binding), ", ")}
                      {if mcp_catalog_source(binding),
                        do: " [#{mcp_catalog_source(binding)}]",
                        else: ""}
                    </p>
                    <div class="mt-2 text-xs text-[var(--hx-mute)]">
                      {if binding.enabled, do: "enabled", else: "disabled"} · {mcp_health_label(
                        agent.mcp_statuses[binding.mcp_server_config_id]
                      )} · {mcp_action_count(binding)} actions
                    </div>
                  </div>
                  <p :if={agent.mcp_servers == []} class="text-sm text-[var(--hx-mute)]">
                    No MCP integrations bound to this agent yet.
                  </p>
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
            <.input
              field={@form[:role]}
              type="select"
              label="Role"
              options={role_options()}
            />
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
      work_items: Runtime.list_work_items(limit: 500) |> length(),
      turns:
        Runtime.list_conversations(limit: 200)
        |> Enum.flat_map(&Runtime.list_turns(&1.id))
        |> length(),
      memories: HydraX.Memory.list_memories(limit: 1_000) |> length()
    }
  end

  defp agents_with_runtime do
    agents = Runtime.list_agents()
    mcp_statuses = Runtime.mcp_statuses() |> Map.new(&{&1.id, &1})
    autonomy_status = Runtime.autonomy_status()
    worker_pressure = Map.new(autonomy_status.worker_pressure || [], &{&1.agent_id, &1})
    role_queue_backlog = Map.new(autonomy_status.role_queue_backlog || [], &{&1.role, &1})

    delegation_supervision =
      autonomy_status.delegation_supervision
      |> List.wrap()
      |> Enum.group_by(& &1.agent_id)
      |> Map.new(fn {agent_id, entries} ->
        {agent_id, merge_agent_delegation_supervision(entries)}
      end)

    scheduler_status = Runtime.scheduler_status()
    dispatch_results = List.wrap(scheduler_status.role_queue_dispatches[:results] || [])

    assignment_recovery_results =
      List.wrap(scheduler_status.assignment_recoveries[:results] || [])

    stale_claim_cleanup_results =
      List.wrap(scheduler_status.stale_work_item_claims[:results] || [])

    active_agent_ids =
      agents
      |> Enum.filter(&(&1.status == "active"))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    orphaned_role_counts =
      Runtime.list_work_items(limit: 500, preload: false)
      |> Enum.filter(fn work_item ->
        work_item.status not in ["completed", "failed", "canceled"] and
          is_integer(work_item.assigned_agent_id) and
          is_binary(work_item.assigned_role) and
          not MapSet.member?(active_agent_ids, work_item.assigned_agent_id)
      end)
      |> Enum.frequencies_by(& &1.assigned_role)

    agents
    |> Enum.map(fn agent ->
      role_backlog = Map.get(role_queue_backlog, agent.role, %{})
      pressure = Map.get(worker_pressure, agent.id, %{})
      orphaned_role_count = Map.get(orphaned_role_counts, agent.role, 0)

      agent
      |> Map.put(:runtime, Runtime.agent_runtime_status(agent))
      |> Map.put(:capability_profile, Runtime.capability_profile(agent))
      |> Map.put(
        :capability_summary,
        Runtime.capability_profile(agent) |> Runtime.Autonomy.capability_summary()
      )
      |> Map.put(:provider_route, Runtime.effective_provider_route(agent.id, "channel"))
      |> Map.put(:effective_policy, Runtime.effective_policy(agent.id, process_type: "channel"))
      |> Map.put(:bulletin, Runtime.agent_bulletin(agent.id))
      |> Map.put(:compaction_policy, Runtime.compaction_policy(agent.id))
      |> Map.put(
        :recent_work_items,
        Runtime.list_work_items(agent_id: agent.id, limit: 4)
        |> Enum.map(&attach_promoted_work_item_memories/1)
      )
      |> Map.put(
        :work_queue,
        work_queue_summary(agent.id, role_backlog, pressure, orphaned_role_count)
      )
      |> Map.put(:role_queue_backlog, role_backlog)
      |> Map.put(:worker_pressure, pressure)
      |> Map.put(:delegation_supervision, Map.get(delegation_supervision, agent.id, %{}))
      |> Map.put(:orphaned_role_count, orphaned_role_count)
      |> Map.put(:recent_role_dispatch, recent_role_dispatch_summary(dispatch_results, agent.id))
      |> Map.put(
        :recent_assignment_recovery,
        recent_assignment_recovery_summary(assignment_recovery_results, agent.id)
      )
      |> Map.put(
        :recent_stale_claim_cleanup,
        recent_stale_claim_cleanup_summary(stale_claim_cleanup_results, agent.id)
      )
      |> Map.put(:tool_policy_override, Runtime.get_agent_tool_policy(agent.id))
      |> Map.put(:effective_tool_policy, Runtime.effective_tool_policy(agent.id))
      |> Map.put(:control_policy_override, Runtime.get_agent_control_policy(agent.id))
      |> Map.put(:effective_control_policy, Runtime.effective_control_policy(agent.id))
      |> Map.put(:skills, Runtime.list_skills(agent_id: agent.id))
      |> Map.put(:mcp_servers, Runtime.list_agent_mcp_servers(agent.id))
      |> Map.put(:mcp_statuses, mcp_statuses)
    end)
  end

  defp merge_agent_delegation_supervision([entry]), do: entry

  defp merge_agent_delegation_supervision(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      %{
        agent_id: entry[:agent_id] || acc[:agent_id],
        agent_name: entry[:agent_name] || acc[:agent_name],
        role: acc[:role] || entry[:role],
        active_batches: (acc[:active_batches] || 0) + (entry[:active_batches] || 0),
        occupied_batches: (acc[:occupied_batches] || 0) + (entry[:occupied_batches] || 0),
        deferred_batches: (acc[:deferred_batches] || 0) + (entry[:deferred_batches] || 0),
        pending_children: (acc[:pending_children] || 0) + (entry[:pending_children] || 0),
        active_children: (acc[:active_children] || 0) + (entry[:active_children] || 0),
        terminal_children: (acc[:terminal_children] || 0) + (entry[:terminal_children] || 0),
        constrained_roles:
          merge_role_frequency_maps(acc[:constrained_roles], entry[:constrained_roles]),
        constrained_role_pressure:
          merge_role_pressure_maps(
            acc[:constrained_role_pressure],
            entry[:constrained_role_pressure]
          ),
        missing_required_roles:
          merge_role_frequency_maps(
            acc[:missing_required_roles],
            entry[:missing_required_roles]
          ),
        pressure_batches:
          merge_pressure_batch_counts(acc[:pressure_batches], entry[:pressure_batches]),
        repeatedly_deferred_batches:
          (acc[:repeatedly_deferred_batches] || 0) +
            (entry[:repeatedly_deferred_batches] || 0),
        total_expansion_deferrals:
          (acc[:total_expansion_deferrals] || 0) + (entry[:total_expansion_deferrals] || 0),
        max_expansion_deferrals:
          max(acc[:max_expansion_deferrals] || 0, entry[:max_expansion_deferrals] || 0),
        required_role_gap_count:
          (acc[:required_role_gap_count] || 0) + (entry[:required_role_gap_count] || 0),
        urgent_batches: (acc[:urgent_batches] || 0) + (entry[:urgent_batches] || 0),
        supervision_budget: max(acc[:supervision_budget] || 0, entry[:supervision_budget] || 0),
        supervision_budget_remaining:
          min_remaining_budget(
            acc[:supervision_budget_remaining],
            entry[:supervision_budget_remaining]
          ),
        supervision_batch_budget:
          max(acc[:supervision_batch_budget] || 0, entry[:supervision_batch_budget] || 0),
        supervision_batch_budget_remaining:
          min_remaining_budget(
            acc[:supervision_batch_budget_remaining],
            entry[:supervision_batch_budget_remaining]
          ),
        highest_priority: max(acc[:highest_priority] || 0, entry[:highest_priority] || 0)
      }
    end)
  end

  defp merge_agent_delegation_supervision(_entries), do: %{}

  defp merge_role_frequency_maps(left, right) do
    [left || %{}, right || %{}]
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.reduce(%{}, fn {role, count}, acc ->
      Map.update(acc, role, count, &(&1 + count))
    end)
  end

  defp merge_role_pressure_maps(left, right) do
    [left || %{}, right || %{}]
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.reduce(%{}, fn {role, pressure}, acc ->
      Map.update(acc, role, pressure || %{}, fn current ->
        %{
          urgent_queued_count:
            max(
              current[:urgent_queued_count] || current["urgent_queued_count"] || 0,
              pressure[:urgent_queued_count] || pressure["urgent_queued_count"] || 0
            ),
          urgent_deferred_count:
            max(
              current[:urgent_deferred_count] || current["urgent_deferred_count"] || 0,
              pressure[:urgent_deferred_count] || pressure["urgent_deferred_count"] || 0
            ),
          saturated_workers:
            max(
              current[:saturated_workers] || current["saturated_workers"] || 0,
              pressure[:saturated_workers] || pressure["saturated_workers"] || 0
            ),
          idle_workers:
            max(
              current[:idle_workers] || current["idle_workers"] || 0,
              pressure[:idle_workers] || pressure["idle_workers"] || 0
            ),
          available_workers:
            max(
              current[:available_workers] || current["available_workers"] || 0,
              pressure[:available_workers] || pressure["available_workers"] || 0
            )
        }
      end)
    end)
  end

  defp merge_pressure_batch_counts(left, right) do
    %{
      high: ((left || %{})[:high] || 0) + ((right || %{})[:high] || 0),
      medium: ((left || %{})[:medium] || 0) + ((right || %{})[:medium] || 0),
      low: ((left || %{})[:low] || 0) + ((right || %{})[:low] || 0)
    }
  end

  defp min_remaining_budget(nil, value), do: value
  defp min_remaining_budget(value, nil), do: value
  defp min_remaining_budget(left, right), do: min(left, right)

  defp compaction_policy_form(agent) do
    %{
      "soft" => agent.compaction_policy.soft,
      "medium" => agent.compaction_policy.medium,
      "hard" => agent.compaction_policy.hard
    }
  end

  defp work_queue_summary(agent_id, role_backlog, pressure, orphaned_role_count) do
    items = Runtime.list_work_items(agent_id: agent_id, limit: 100, preload: false)

    %{
      pending_review: Enum.count(items, &(&1.status == "blocked" and &1.review_required)),
      awaiting_operator:
        Enum.count(items, &(&1.status == "completed" and &1.approval_stage == "validated")),
      extensions_gated:
        Enum.count(
          items,
          &(&1.kind == "extension" and &1.status == "completed" and
              &1.approval_stage in ["validated", "operator_approved"])
        ),
      blocked_or_failed: Enum.count(items, &(&1.status in ["blocked", "failed"])),
      role_backlog: role_backlog[:queued_count] || 0,
      capacity_posture: pressure[:capacity_posture] || "idle",
      orphaned_role_assignments: orphaned_role_count
    }
  end

  defp worker_pressure_detail(pressure) when is_map(pressure) do
    if map_size(pressure) == 0 do
      nil
    else
      "worker pressure open #{pressure[:assigned_open_count] || 0} · claims #{pressure[:active_claimed_count] || 0} · stale #{pressure[:stale_claimed_count] || 0} · blocked #{pressure[:blocked_count] || 0} · failed #{pressure[:failed_count] || 0} · urgent backlog #{pressure[:urgent_shared_role_queue_count] || 0}/#{pressure[:urgent_deferred_role_queue_count] || 0}"
    end
  end

  defp delegation_supervision_detail(%{active_batches: active_batches} = summary)
       when is_integer(active_batches) and active_batches > 0 do
    constrained_line =
      case summary[:constrained_roles] || %{} do
        constrained when constrained == %{} ->
          nil

        constrained ->
          constrained
          |> Enum.sort_by(fn {role, _count} -> role end)
          |> Enum.map_join(", ", fn {role, count} ->
            pressure =
              get_in(summary, [:constrained_role_pressure, role]) ||
                get_in(summary, ["constrained_role_pressure", role]) || %{}

            "#{role} x#{count}" <>
              delegation_constraint_pressure_suffix(pressure)
          end)
          |> then(&"constrained #{&1}")
      end

    [
      "delegation supervision #{active_batches} batches",
      delegation_supervision_budget_label(summary),
      delegation_supervision_batch_budget_label(summary),
      delegation_supervision_urgent_batches_label(summary),
      delegation_supervision_missing_roles_label(summary),
      delegation_supervision_pressure_label(summary),
      delegation_supervision_deferral_pressure_label(summary),
      delegation_deferred_batches_label(summary[:deferred_batches] || 0),
      "pending #{summary[:pending_children] || 0}",
      "active #{summary[:active_children] || 0}",
      "terminal #{summary[:terminal_children] || 0}",
      constrained_line
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp delegation_supervision_detail(_summary), do: nil

  defp delegation_constraint_pressure_suffix(pressure) when is_map(pressure) do
    urgent_queued = pressure[:urgent_queued_count] || pressure["urgent_queued_count"] || 0

    urgent_deferred =
      pressure[:urgent_deferred_count] || pressure["urgent_deferred_count"] || 0

    saturated = pressure[:saturated_workers] || pressure["saturated_workers"] || 0

    available =
      (pressure[:idle_workers] || pressure["idle_workers"] || 0) +
        (pressure[:available_workers] || pressure["available_workers"] || 0)

    " (urgent #{urgent_queued}/#{urgent_deferred}, sat #{saturated}, avail #{available})"
  end

  defp delegation_constraint_pressure_suffix(_pressure), do: ""

  defp delegation_supervision_budget_label(summary) when is_map(summary) do
    budget = summary[:supervision_budget]
    remaining = summary[:supervision_budget_remaining]

    if is_integer(budget) and is_integer(remaining) do
      "budget #{budget} · remaining #{remaining}"
    end
  end

  defp delegation_supervision_budget_label(_summary), do: nil

  defp delegation_supervision_batch_budget_label(summary) when is_map(summary) do
    budget = summary[:supervision_batch_budget]
    remaining = summary[:supervision_batch_budget_remaining]

    if is_integer(budget) and is_integer(remaining) do
      "batch budget #{budget} · remaining #{remaining}"
    end
  end

  defp delegation_supervision_batch_budget_label(_summary), do: nil

  defp delegation_supervision_urgent_batches_label(summary) when is_map(summary) do
    count = summary[:urgent_batches]

    if is_integer(count) and count > 0 do
      "urgent #{count}"
    end
  end

  defp delegation_supervision_urgent_batches_label(_summary), do: nil

  defp delegation_supervision_missing_roles_label(summary) when is_map(summary) do
    case summary[:missing_required_roles] || %{} do
      requirements when requirements == %{} ->
        nil

      requirements ->
        "required roles #{format_delegation_role_requirements(requirements)}"
    end
  end

  defp delegation_supervision_missing_roles_label(_summary), do: nil

  defp delegation_supervision_pressure_label(summary) when is_map(summary) do
    counts = summary[:pressure_batches] || %{}
    high = counts[:high] || 0
    medium = counts[:medium] || 0
    low = counts[:low] || 0

    if high > 0 or medium > 0 or low > 0 do
      "pressure h#{high} m#{medium} l#{low}"
    end
  end

  defp delegation_supervision_pressure_label(_summary), do: nil

  defp delegation_supervision_deferral_pressure_label(summary) when is_map(summary) do
    repeated = summary[:repeatedly_deferred_batches] || 0
    max_deferrals = summary[:max_expansion_deferrals] || 0

    if repeated > 0 or max_deferrals > 1 do
      "repeat deferrals #{repeated} · max #{max_deferrals}"
    end
  end

  defp delegation_supervision_deferral_pressure_label(_summary), do: nil

  defp delegation_deferred_batches_label(count) when is_integer(count) and count > 0,
    do: "deferred #{count}"

  defp delegation_deferred_batches_label(_count), do: nil

  defp recent_role_dispatch_summary(results, agent_id) do
    agent_results = Enum.filter(results, &((&1[:agent_id] || &1["agent_id"]) == agent_id))

    case Enum.find(agent_results, fn result ->
           action = result[:action] || result["action"]
           action not in [nil, "idle"]
         end) do
      nil ->
        if agent_results == [] do
          nil
        else
          "recent role dispatch idle"
        end

      result ->
        action = result[:action] || result["action"]
        work_item_id = result[:work_item_id] || result["work_item_id"]
        posture = result[:capacity_posture] || result["capacity_posture"]
        lease_owner = result[:lease_owner] || result["lease_owner"]
        priority_reason = result[:priority_reason] || result["priority_reason"]
        priority_urgency = result[:priority_urgency] || result["priority_urgency"]

        deferred_until =
          result[:deferred_until] || result["deferred_until"] || result[:lease_expires_at] ||
            result["lease_expires_at"]

        priority_detail =
          if priority_reason == "required_role" and is_integer(priority_urgency) and
               priority_urgency > 0 do
            " · required role x#{priority_urgency}"
          end

        case action do
          "worker_saturated" ->
            "recent role dispatch saturated#{if is_binary(posture), do: " (#{posture})", else: ""}#{priority_detail || ""}#{if cooldown = recovery_deferred_label(deferred_until), do: " · #{cooldown}", else: ""}"

          "claimed_remote" ->
            "recent role dispatch claimed remotely#{if work_item_id, do: " ##{work_item_id}", else: ""}#{if is_binary(lease_owner), do: " by #{lease_owner}", else: ""}#{priority_detail || ""}#{if cooldown = recovery_deferred_label(deferred_until), do: " · #{cooldown}", else: ""}"

          _ ->
            "recent role dispatch #{action}#{if work_item_id, do: " ##{work_item_id}", else: ""}#{priority_detail || ""}"
        end
    end
  end

  defp recent_assignment_recovery_summary(results, agent_id) do
    agent_results =
      Enum.filter(results, &((&1[:assigned_agent_id] || &1["assigned_agent_id"]) == agent_id))

    case List.first(agent_results) do
      nil ->
        nil

      result ->
        action = result[:action] || result["action"]
        work_item_id = result[:work_item_id] || result["work_item_id"]
        posture = result[:capacity_posture] || result["capacity_posture"]
        queue_reason = result[:queue_reason] || result["queue_reason"]
        deferred_until = result[:deferred_until] || result["deferred_until"]

        detail =
          case {queue_reason, posture, recovery_deferred_label(deferred_until)} do
            {"worker_saturated", posture, cooldown}
            when is_binary(posture) and is_binary(cooldown) ->
              " · worker saturated (#{posture}) · #{cooldown}"

            {"worker_saturated", posture, _cooldown} when is_binary(posture) ->
              " · worker saturated (#{posture})"

            {_, posture, cooldown}
            when is_binary(posture) and is_binary(cooldown) and
                   action in ["reassigned_queued", "reassigned_executed"] ->
              " · #{posture} · #{cooldown}"

            {_, posture, _cooldown}
            when is_binary(posture) and action in ["reassigned_queued", "reassigned_executed"] ->
              " · #{posture}"

            _ ->
              ""
          end

        action_label =
          case action do
            "reassigned_queued" -> "queued"
            "reassigned_executed" -> "executed"
            other -> other
          end

        "recent assignment recovery #{action_label}#{if work_item_id, do: " ##{work_item_id}", else: ""}#{detail}"
    end
  end

  defp recent_stale_claim_cleanup_summary(results, agent_id) do
    agent_results =
      Enum.filter(results, &((&1[:assigned_agent_id] || &1["assigned_agent_id"]) == agent_id))

    case Enum.find(agent_results, fn result ->
           action = result[:action] || result["action"]
           action not in [nil, "idle"]
         end) do
      nil ->
        nil

      result ->
        action = result[:action] || result["action"]
        work_item_id = result[:work_item_id] || result["work_item_id"]
        reason = result[:reason] || result["reason"]

        detail =
          if is_binary(reason) do
            " (#{reason})"
          else
            ""
          end

        "recent stale cleanup #{action}#{if work_item_id, do: " ##{work_item_id}", else: ""}#{detail}"
    end
  end

  defp recovery_deferred_label(nil), do: nil

  defp recovery_deferred_label(%DateTime{} = value) do
    "cooldown until #{Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")}"
  end

  defp recovery_deferred_label(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> recovery_deferred_label(datetime)
      _ -> "cooldown until #{value}"
    end
  end

  defp recovery_deferred_label(_value), do: nil

  defp work_item_latest_approval(work_item) do
    work_item.approval_records
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> List.first()
    |> case do
      nil -> "pending"
      record -> record.decision
    end
  end

  defp work_item_last_action(work_item) do
    get_in(work_item.result_refs || %{}, ["last_requested_action"])
  end

  defp work_item_enablement_status(work_item) do
    get_in(work_item.result_refs || %{}, ["extension_enablement_status"])
  end

  defp work_item_artifact_types(work_item) do
    work_item.artifacts
    |> Enum.map(& &1.type)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp work_item_actionable?(work_item) do
    work_item_primary_action(work_item) != nil
  end

  defp work_item_primary_action(%{kind: "extension", status: "completed", approval_stage: stage})
       when stage in ["validated", "operator_approved"],
       do: "enable_extension"

  defp work_item_primary_action(%{
         metadata: %{"task_type" => "publish_approval"},
         status: "completed",
         approval_stage: "validated"
       }),
       do: "publish_review_report"

  defp work_item_primary_action(%{
         kind: "engineering",
         status: "completed",
         approval_stage: "validated"
       }),
       do: "merge_ready"

  defp work_item_primary_action(%{status: "completed", approval_stage: "validated"}),
    do: "promote_work_item"

  defp work_item_primary_action(%{status: "completed", approval_stage: "operator_approved"}),
    do: "promote_work_item"

  defp work_item_primary_action(_work_item), do: nil

  defp work_item_primary_action_label(work_item) do
    case work_item_primary_action(work_item) do
      "enable_extension" ->
        "Approve extension"

      "merge_ready" ->
        if(degraded_work_item?(work_item),
          do: "Promote constrained patch",
          else: "Promote to merge-ready"
        )

      "publish_review_report" ->
        "Approve degraded delivery"

      "promote_work_item" ->
        if(degraded_work_item?(work_item),
          do: "Promote degraded findings",
          else: "Promote findings"
        )

      _ ->
        "Approve"
    end
  end

  defp provider_routing_form(agent) do
    profile = Runtime.provider_routing_profile(agent.id)

    %{
      "default_provider_id" => profile["default_provider_id"],
      "fallback_provider_ids_csv" => Enum.join(profile["fallback_provider_ids"] || [], ","),
      "channel_provider_id" => get_in(profile, ["process_overrides", "channel"]),
      "scheduler_provider_id" => get_in(profile, ["process_overrides", "scheduler"]),
      "cortex_provider_id" => get_in(profile, ["process_overrides", "cortex"]),
      "compactor_provider_id" => get_in(profile, ["process_overrides", "compactor"])
    }
  end

  defp role_options do
    Runtime.Autonomy.role_options()
  end

  defp list_summary(values) do
    case Enum.reject(List.wrap(values), &(&1 in [nil, ""])) do
      [] -> "none"
      entries -> Enum.join(entries, ", ")
    end
  end

  defp work_item_artifact_summary(item) do
    item.result_refs
    |> Map.get("artifact_ids", [])
    |> List.wrap()
    |> length()
    |> then(&"artifacts #{&1}")
  end

  defp attach_promoted_work_item_memories(work_item) do
    Map.put(work_item, :promoted_memories, Runtime.promoted_work_item_memories(work_item))
  end

  defp work_item_promoted_memories(work_item) do
    Map.get(work_item, :promoted_memories, [])
  end

  defp work_item_promoted_memory_summary(work_item) do
    memories = work_item_promoted_memories(work_item)

    case memories do
      [] ->
        nil

      entries ->
        "promoted #{length(entries)} findings"
    end
  end

  defp work_item_promoted_memory_labels(work_item) do
    work_item
    |> work_item_promoted_memories()
    |> Enum.take(3)
    |> Enum.map(fn memory ->
      "#{memory.type}: #{truncate_text(memory.content, 60)}"
    end)
  end

  defp work_item_publish_summary(work_item) do
    cond do
      get_in(work_item.metadata || %{}, ["task_type"]) == "delegation_pressure_operator_follow_up" ->
        [
          delegation_pressure_operator_status_label(work_item.status),
          delegation_pressure_reason_summary(work_item)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")

      get_in(work_item.metadata || %{}, ["task_type"]) == "publish_approval" ->
        delivery = get_in(work_item.metadata || %{}, ["delivery"]) || %{}
        delivery_result = get_in(work_item.result_refs || %{}, ["delivery"]) || %{}

        prefix =
          case delivery_result["status"] do
            "delivered" -> "degraded delivery approved"
            "blocked" -> "degraded delivery blocked"
            "failed" -> "degraded delivery failed"
            "rejected" -> "degraded delivery rejected"
            _ -> "degraded delivery awaiting approval"
          end

        [
          prefix,
          delivery["channel"] || delivery["mode"] || "report",
          delivery["target"] && "-> #{delivery["target"]}",
          publish_recovery_summary(work_item)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")

      get_in(work_item.metadata || %{}, ["task_type"]) == "publish_summary" ->
        delivery = get_in(work_item.metadata || %{}, ["delivery"]) || %{}
        delivery_result = work_item_publish_delivery_result(work_item)

        channel =
          delivery_result["channel"] || delivery["channel"] || delivery["mode"] || "report"

        target = delivery_result["target"] || delivery["target"]
        artifact_types = work_item_artifact_types(work_item)

        prefix =
          case delivery_result["status"] do
            "delivered" ->
              if(delivery_result["degraded"], do: "delivery degraded", else: "delivery delivered")

            "blocked" ->
              "delivery blocked"

            "failed" ->
              "delivery failed"

            "rejected" ->
              if(delivery_result["degraded"],
                do: "delivery degraded rejected",
                else: "delivery rejected"
              )

            "draft" ->
              if(delivery_result["degraded"],
                do: "delivery degraded draft",
                else: "delivery draft"
              )

            "skipped" ->
              if(delivery_result["reason"] == "internal_report_recovery",
                do: "delivery internal",
                else: "delivery skipped"
              )

            _ ->
              if work_item.status == "completed" and "delivery_brief" in artifact_types do
                "delivery brief ready"
              else
                "publish task #{work_item.status}"
              end
          end

        [
          prefix,
          channel,
          target && "-> #{target}",
          publish_recovery_summary(work_item),
          publish_replan_summary(work_item)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")

      List.wrap(get_in(work_item.result_refs || %{}, ["child_work_item_ids"])) != [] and
          work_item.status == "blocked" ->
        count =
          work_item.result_refs
          |> Map.get("child_work_item_ids", [])
          |> List.wrap()
          |> length()

        if degraded_work_item?(work_item) do
          "degraded review queued #{count}"
        else
          "review queued #{count}"
        end

      List.wrap(get_in(work_item.result_refs || %{}, ["follow_up_work_item_ids"])) != [] ->
        count = follow_up_queue_count(work_item)
        strategy = follow_up_queue_strategy_detail(work_item)
        alternatives = follow_up_queue_alternative_detail(work_item)

        case follow_up_queue_type(work_item) do
          "replan" ->
            [
              "replan follow-up queued #{count}",
              [strategy, alternatives]
              |> Enum.reject(&(&1 in [nil, ""]))
              |> case do
                [] -> nil
                details -> "(" <> Enum.join(details, "; ") <> ")"
              end
            ]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join(" ")

          "publish" ->
            "publish follow-up queued #{count}"

          _ ->
            "follow-up queued #{count}"
        end

      true ->
        nil
    end
  end

  defp work_item_publish_detail_lines(work_item) do
    [
      work_item_assignment_detail_line(work_item),
      delegation_pressure_reason_line(work_item),
      delegation_pressure_strategy_line(work_item),
      publish_objective_line(work_item),
      publish_prior_decision_line(work_item),
      publish_decision_comparison_line(work_item),
      publish_review_decision_line(work_item),
      publish_synthesis_decision_line(work_item),
      publish_rationale_line(work_item),
      publish_confidence_line(work_item),
      publish_guidance_line(work_item)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      details -> details
    end
  end

  defp delegation_pressure_operator_status_label("completed"),
    do: "operator intervention prepared"

  defp delegation_pressure_operator_status_label("failed"), do: "operator intervention failed"
  defp delegation_pressure_operator_status_label("blocked"), do: "operator intervention blocked"
  defp delegation_pressure_operator_status_label("canceled"), do: "operator intervention canceled"
  defp delegation_pressure_operator_status_label(_status), do: "operator intervention queued"

  defp delegation_pressure_reason_summary(work_item) do
    case get_in(work_item.metadata || %{}, ["reason"]) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp delegation_pressure_reason_line(work_item) do
    case get_in(work_item.metadata || %{}, ["reason"]) do
      value when is_binary(value) and value != "" -> "reason #{value}"
      _ -> nil
    end
  end

  defp delegation_pressure_strategy_line(work_item) do
    case get_in(work_item.metadata || %{}, ["constraint_strategy"]) do
      value when is_binary(value) and value != "" -> "constraint strategy #{value}"
      _ -> nil
    end
  end

  defp work_item_delegation_summary(work_item) do
    case Runtime.delegation_batch_snapshot(work_item) do
      %{"expected_count" => expected_count} = snapshot ->
        [
          "delegation batch #{expected_count}",
          "active #{snapshot["active_count"] || 0}",
          delegation_pending_summary(snapshot),
          "terminal #{snapshot["terminal_count"] || 0}"
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" · ")

      _ ->
        nil
    end
  end

  defp work_item_delegation_detail_lines(work_item) do
    case Runtime.delegation_batch_snapshot(work_item) do
      %{} = snapshot ->
        [
          "delegation #{snapshot["mode"]} · strategy #{snapshot["batch_strategy"] || "ordered"} · concurrency #{snapshot["batch_concurrency"] || 1} · completed #{snapshot["completed_count"] || 0} · failed #{snapshot["failed_count"] || 0} · canceled #{snapshot["canceled_count"] || 0}",
          delegation_roles_line(snapshot),
          delegation_pending_roles_line(snapshot),
          delegation_quorum_line(snapshot),
          delegation_role_quorum_line(snapshot),
          delegation_missing_role_quorum_line(snapshot),
          delegation_quorum_skip_line(snapshot),
          delegation_supervision_budget_line(snapshot),
          delegation_batch_budget_line(snapshot),
          delegation_expansion_history_line(snapshot),
          delegation_deferral_history_line(snapshot),
          delegation_expansion_pressure_line(snapshot),
          delegation_expansion_severity_line(snapshot),
          delegation_expansion_cooldown_line(snapshot)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> case do
          [] -> nil
          details -> details
        end

      _ ->
        nil
    end
  end

  defp delegation_roles_line(%{"roles" => roles}) when is_list(roles) and roles != [] do
    "delegation roles #{Enum.join(roles, ", ")}"
  end

  defp delegation_roles_line(_snapshot), do: nil

  defp delegation_pending_roles_line(%{"pending_roles" => pending_roles})
       when is_map(pending_roles) and map_size(pending_roles) > 0 do
    pending_roles =
      pending_roles
      |> Enum.sort_by(fn {role, _count} -> role end)
      |> Enum.map_join(", ", fn {role, count} -> "#{role} x#{count}" end)

    "pending roles #{pending_roles}"
  end

  defp delegation_pending_roles_line(_snapshot), do: nil

  defp delegation_quorum_line(%{"completion_quorum" => quorum, "quorum_met" => true})
       when is_integer(quorum) and quorum > 0 do
    "completion quorum #{quorum} met"
  end

  defp delegation_quorum_line(%{"completion_quorum" => quorum})
       when is_integer(quorum) and quorum > 0 do
    "completion quorum #{quorum}"
  end

  defp delegation_quorum_line(_snapshot), do: nil

  defp delegation_role_quorum_line(%{
         "completion_role_requirements" => requirements,
         "role_quorum_met" => true
       })
       when map_size(requirements) > 0 do
    "role quorum #{format_delegation_role_requirements(requirements)} met"
  end

  defp delegation_role_quorum_line(%{"completion_role_requirements" => requirements})
       when map_size(requirements) > 0 do
    "role quorum #{format_delegation_role_requirements(requirements)}"
  end

  defp delegation_role_quorum_line(_snapshot), do: nil

  defp delegation_missing_role_quorum_line(%{"missing_completion_roles" => requirements})
       when map_size(requirements) > 0 do
    "missing role quorum #{format_delegation_role_requirements(requirements)}"
  end

  defp delegation_missing_role_quorum_line(_snapshot), do: nil

  defp delegation_quorum_skip_line(%{"quorum_skipped_count" => count})
       when is_integer(count) and count > 0 do
    "quorum skipped #{count}"
  end

  defp delegation_quorum_skip_line(_snapshot), do: nil

  defp format_delegation_role_requirements(requirements) when is_map(requirements) do
    requirements
    |> Enum.sort_by(fn {role, _count} -> role end)
    |> Enum.map_join(", ", fn {role, count} -> "#{role} x#{count}" end)
  end

  defp delegation_supervision_budget_line(%{
         "supervision_budget" => budget,
         "supervision_active_children" => active_children
       })
       when is_integer(budget) and is_integer(active_children) do
    "supervision budget #{budget} · active children #{active_children}"
  end

  defp delegation_supervision_budget_line(_snapshot), do: nil

  defp delegation_batch_budget_line(%{
         "batch_budget" => budget,
         "supervision_active_batches" => active_batches
       })
       when is_integer(budget) and is_integer(active_batches) do
    "batch budget #{budget} · active batches #{active_batches}"
  end

  defp delegation_batch_budget_line(_snapshot), do: nil

  defp delegation_expansion_history_line(%{"expansion_count" => count} = snapshot)
       when is_integer(count) and count > 0 do
    last_expanded =
      case snapshot["last_expanded_at"] do
        %DateTime{} = value ->
          " · last expanded #{Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")}"

        _ ->
          ""
      end

    "expanded #{count}#{last_expanded}"
  end

  defp delegation_expansion_history_line(_snapshot), do: nil

  defp delegation_deferral_history_line(%{"expansion_deferred_count" => count} = snapshot)
       when is_integer(count) and count > 0 do
    suffix =
      case snapshot["last_deferred_at"] do
        %DateTime{} = value ->
          " · last deferred #{Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")}"

        _ ->
          ""
      end

    "deferred #{count}#{suffix}"
  end

  defp delegation_deferral_history_line(_snapshot), do: nil

  defp delegation_expansion_pressure_line(%{"expansion_pressure_snapshot" => pressure_map})
       when is_map(pressure_map) and map_size(pressure_map) > 0 do
    pressure_map =
      pressure_map
      |> Enum.sort_by(fn {role, _pressure} -> role end)
      |> Enum.map_join(", ", fn {role, pressure} ->
        pending = pressure["pending_count"] || 0
        urgent_queued = pressure["urgent_queued_count"] || 0
        urgent_deferred = pressure["urgent_deferred_count"] || 0
        available = (pressure["idle_workers"] || 0) + (pressure["available_workers"] || 0)
        saturated = pressure["saturated_workers"] || 0

        "#{role} x#{pending} (urgent #{urgent_queued}/#{urgent_deferred}, sat #{saturated}, avail #{available})"
      end)

    "expansion pressure #{pressure_map}"
  end

  defp delegation_expansion_pressure_line(_snapshot), do: nil

  defp delegation_expansion_severity_line(%{
         "expansion_pressure_severity" => severity,
         "expansion_delay_seconds" => delay_seconds
       })
       when is_binary(severity) and is_integer(delay_seconds) do
    "expansion severity #{severity} · delay #{delay_seconds}s"
  end

  defp delegation_expansion_severity_line(_snapshot), do: nil

  defp delegation_expansion_cooldown_line(%{"expansion_deferred_until" => value})
       when not is_nil(value) do
    case recovery_deferred_label(value) do
      nil -> nil
      label -> "expansion deferred · #{label}"
    end
  end

  defp delegation_expansion_cooldown_line(_snapshot), do: nil

  defp delegation_pending_summary(%{"pending_count" => count})
       when is_integer(count) and count > 0,
       do: "pending #{count}"

  defp delegation_pending_summary(_snapshot), do: nil

  defp work_item_assignment_summary(work_item) do
    resolution = get_in(work_item.metadata || %{}, ["assignment_resolution"]) || %{}

    case {resolution["resolved_agent_name"], resolution["strategy"]} do
      {name, strategy} when is_binary(name) and is_binary(strategy) ->
        "assigned #{name} via #{humanize_assignment_strategy(strategy)}"

      _ ->
        nil
    end
  end

  defp work_item_assignment_detail_line(work_item) do
    resolution = get_in(work_item.metadata || %{}, ["assignment_resolution"]) || %{}

    case {resolution["resolved_agent_name"], resolution["reasons"]} do
      {name, reasons} when is_binary(name) and is_list(reasons) and reasons != [] ->
        "assignment #{name}: #{Enum.join(reasons, ", ")}"

      {name, _reasons} when is_binary(name) ->
        "assignment #{name}"

      _ ->
        nil
    end
  end

  defp humanize_assignment_strategy("role_capability_match"), do: "role capability match"
  defp humanize_assignment_strategy("capability_fallback"), do: "capability fallback"
  defp humanize_assignment_strategy("worker_claim"), do: "worker claim"
  defp humanize_assignment_strategy("inactive_reassignment"), do: "inactive reassignment"
  defp humanize_assignment_strategy("replay_reassignment"), do: "replay reassignment"
  defp humanize_assignment_strategy(strategy) when is_binary(strategy), do: strategy
  defp humanize_assignment_strategy(_strategy), do: "assignment"

  defp follow_up_queue_type(work_item) do
    work_item
    |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "types"]))
    |> List.wrap()
    |> List.first()
    |> Kernel.||("publish")
  end

  defp follow_up_queue_count(work_item) do
    get_in(work_item.result_refs || %{}, ["follow_up_summary", "count"]) ||
      work_item.result_refs
      |> Map.get("follow_up_work_item_ids", [])
      |> List.wrap()
      |> length()
  end

  defp follow_up_queue_strategy_detail(work_item) do
    summary =
      work_item
      |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "summaries"]))
      |> List.wrap()
      |> case do
        [] ->
          work_item
          |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "strategies"]))
          |> List.wrap()
          |> List.first()
          |> case do
            value when is_binary(value) -> humanize_follow_up_strategy_summary(value)
            _ -> nil
          end
          |> List.wrap()

        entries ->
          entries
      end
      |> List.first()

    if is_binary(summary) and summary != "" do
      summary
    else
      follow_up_queue_strategy(work_item)
      |> case do
        value when is_binary(value) -> humanize_follow_up_strategy(value)
        _ -> nil
      end
    end
  end

  defp follow_up_queue_strategy(work_item) do
    work_item
    |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "strategies"]))
    |> List.wrap()
    |> List.first()
  end

  defp follow_up_queue_alternative_detail(work_item) do
    alternatives =
      work_item
      |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "alternative_summaries"]))
      |> List.wrap()
      |> case do
        [] ->
          work_item
          |> then(&get_in(&1.result_refs || %{}, ["follow_up_summary", "alternative_strategies"]))
          |> List.wrap()
          |> Enum.map(&humanize_follow_up_strategy_summary/1)

        entries ->
          entries
      end
      |> Enum.reject(&(&1 in [nil, ""]))

    if alternatives == [] do
      nil
    else
      "alternatives #{Enum.join(alternatives, ", ")}"
    end
  end

  defp humanize_follow_up_strategy("review_guided_replan"), do: "review-guided"
  defp humanize_follow_up_strategy("operator_guided_replan"), do: "operator-guided"
  defp humanize_follow_up_strategy("narrow_delegate_batch"), do: "narrowed"
  defp humanize_follow_up_strategy("request_review"), do: "review requested"
  defp humanize_follow_up_strategy(strategy) when is_binary(strategy), do: strategy
  defp humanize_follow_up_strategy(_strategy), do: "follow-up"

  defp humanize_follow_up_strategy_summary("review_guided_replan"),
    do: "Reviewer-guided recovery"

  defp humanize_follow_up_strategy_summary("operator_guided_replan"),
    do: "Operator-guided recovery"

  defp humanize_follow_up_strategy_summary("narrow_delegate_batch"),
    do: "Narrowed delegation batch"

  defp humanize_follow_up_strategy_summary("request_review"),
    do: "Review-requested recovery"

  defp humanize_follow_up_strategy_summary(strategy) when is_binary(strategy),
    do: humanize_follow_up_strategy(strategy)

  defp humanize_follow_up_strategy_summary(_strategy), do: nil

  defp work_item_recovery_summary(work_item) do
    metadata = work_item.metadata || %{}

    case metadata["recovery_strategy_summary"] do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        derived_recovery_strategy_summary(metadata)
    end
  end

  defp work_item_recovery_detail_lines(work_item) do
    metadata = work_item.metadata || %{}
    strategy = metadata["preferred_recovery_strategy"]
    behavior = metadata["recovery_strategy_behavior"]
    alternatives = work_item_recovery_alternatives(metadata)

    [
      strategy && "preferred strategy #{humanize_follow_up_strategy(strategy)}",
      behavior && "strategy behavior #{humanize_recovery_strategy_behavior(behavior)}",
      alternatives != [] && "alternative strategies #{Enum.join(alternatives, ", ")}"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
  end

  defp humanize_recovery_strategy_behavior("operator_review_after_execution"),
    do: "operator review after execution"

  defp humanize_recovery_strategy_behavior("review_after_execution"),
    do: "review after execution"

  defp humanize_recovery_strategy_behavior("narrow_scope"), do: "narrow scope"
  defp humanize_recovery_strategy_behavior("constraint_first"), do: "constraint first"
  defp humanize_recovery_strategy_behavior("strategy_guided"), do: "strategy guided"
  defp humanize_recovery_strategy_behavior(behavior) when is_binary(behavior), do: behavior
  defp humanize_recovery_strategy_behavior(_behavior), do: nil

  defp work_item_recovery_alternatives(metadata) do
    metadata["recovery_strategy_alternative_summaries"] ||
      metadata["recovery_strategy_alternatives"]
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(&humanize_follow_up_strategy/1)
  end

  defp derived_recovery_strategy_summary(metadata) do
    strategy = metadata["preferred_recovery_strategy"]

    with value when is_binary(value) and value != "" <- base_recovery_strategy_summary(strategy) do
      if narrowed_delegation_recovery_alternative?(metadata, strategy) do
        "#{value} with narrowed delegation fallback"
      else
        value
      end
    end
  end

  defp base_recovery_strategy_summary("review_guided_replan"), do: "Reviewer-guided recovery"
  defp base_recovery_strategy_summary("operator_guided_replan"), do: "Operator-guided recovery"
  defp base_recovery_strategy_summary("request_review"), do: "Review-requested recovery"
  defp base_recovery_strategy_summary("constraint_replan"), do: "Constraint-first recovery"
  defp base_recovery_strategy_summary("narrow_delegate_batch"), do: "Narrowed delegation batch"

  defp base_recovery_strategy_summary(strategy) when is_binary(strategy),
    do: humanize_follow_up_strategy(strategy)

  defp base_recovery_strategy_summary(_strategy), do: nil

  defp narrowed_delegation_recovery_alternative?(metadata, strategy) do
    strategy != "narrow_delegate_batch" and
      ("narrow_delegate_batch" in List.wrap(metadata["recovery_strategy_alternatives"]) or
         "Narrowed delegation batch" in List.wrap(
           metadata["recovery_strategy_alternative_summaries"]
         ))
  end

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false

  defp work_item_publish_delivery_result(work_item) do
    get_in(work_item.result_refs || %{}, ["delivery"]) ||
      Enum.find_value(work_item.artifacts || [], fn artifact ->
        if artifact.type == "delivery_brief" do
          Map.get(artifact.payload || %{}, "delivery")
        end
      end) || %{}
  end

  defp publish_replan_summary(work_item) do
    if follow_up_queue_type(work_item) == "replan" do
      "replan queued #{follow_up_queue_count(work_item)}"
    end
  end

  defp publish_recovery_summary(work_item) do
    recovery = publish_recovery_snapshot(work_item)
    basis = publish_recovery_basis_label(recovery)

    case recovery["strategy"] do
      "internal_report_fallback" -> "recovery internal-report#{basis}"
      "switch_delivery_channel" -> "recovery switch #{recovery["recommended_channel"]}#{basis}"
      "revise_and_retry_channel" -> "recovery revise+retry#{basis}"
      _ -> nil
    end
  end

  defp publish_objective_line(work_item) do
    case publish_brief_payload(work_item)["publish_objective"] do
      value when is_binary(value) and value != "" -> "objective #{value}"
      _ -> nil
    end
  end

  defp publish_guidance_line(work_item) do
    case publish_brief_payload(work_item)["recommended_actions"] do
      [first | _] when is_binary(first) and first != "" -> "guidance #{first}"
      _ -> nil
    end
  end

  defp publish_rationale_line(work_item) do
    case publish_brief_payload(work_item)["destination_rationale"] do
      value when is_binary(value) and value != "" -> "rationale #{value}"
      _ -> nil
    end
  end

  defp publish_prior_decision_line(work_item) do
    case publish_decision_snapshot(work_item)["prior_summary"] ||
           publish_prior_decision_content(work_item) do
      value when is_binary(value) and value != "" ->
        "prior decision #{value}"

      _ ->
        nil
    end
  end

  defp publish_decision_comparison_line(work_item) do
    case publish_decision_snapshot(work_item)["comparison_summary"] do
      value when is_binary(value) and value != "" ->
        "decision comparison #{value}"

      _ ->
        nil
    end
  end

  defp publish_confidence_line(work_item) do
    payload = publish_brief_payload(work_item)

    case {payload["decision_confidence"], payload["confidence_posture"]} do
      {value, posture} when (is_float(value) or is_integer(value)) and is_binary(posture) ->
        "confidence #{Float.round(value * 1.0, 2)} (#{posture})"

      _ ->
        nil
    end
  end

  defp publish_review_decision_line(work_item) do
    case latest_review_delivery_decision(work_item) do
      %{"content" => value} when is_binary(value) and value != "" ->
        "review decision #{value}"

      _ ->
        nil
    end
  end

  defp publish_synthesis_decision_line(work_item) do
    case latest_synthesis_delivery_decision(work_item) do
      %{"content" => value} when is_binary(value) and value != "" ->
        "synthesis decision #{value}"

      _ ->
        nil
    end
  end

  defp publish_brief_payload(work_item) do
    work_item
    |> Map.get(:artifacts)
    |> case do
      %Ecto.Association.NotLoaded{} -> []
      entries when is_list(entries) -> entries
      _ -> []
    end
    |> Enum.filter(&(&1.type == "delivery_brief"))
    |> Enum.max_by(& &1.id, fn -> nil end)
    |> case do
      nil -> %{}
      artifact -> artifact.payload || %{}
    end
  end

  defp publish_prior_decisions(work_item) do
    get_in(work_item.metadata || %{}, ["follow_up_context", "delivery_decisions"])
    |> List.wrap()
  end

  defp publish_prior_decision_content(work_item) do
    case publish_prior_decisions(work_item) do
      [%{"content" => value} | _] when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp publish_decision_snapshot(work_item) do
    publish_brief_payload(work_item)["delivery_decision_snapshot"] || %{}
  end

  defp latest_review_delivery_decision(work_item) do
    work_item
    |> work_item_artifacts()
    |> Enum.filter(&(&1.type == "review_report"))
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.find_value(fn artifact ->
      artifact.payload
      |> Kernel.||(%{})
      |> Map.get("delivery_decision_context", [])
      |> List.wrap()
      |> Enum.find(&delivery_decision_entry?/1)
    end)
  end

  defp latest_synthesis_delivery_decision(work_item) do
    work_item
    |> work_item_artifacts()
    |> Enum.filter(
      &(&1.type == "decision_ledger" and
          get_in(&1.payload || %{}, ["decision_type"]) == "delegation_synthesis")
    )
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.find_value(fn artifact ->
      artifact.payload
      |> Kernel.||(%{})
      |> Map.get("delivery_decisions", [])
      |> List.wrap()
      |> Enum.find(&delivery_decision_entry?/1)
    end)
  end

  defp work_item_artifacts(work_item) do
    case Map.get(work_item, :artifacts) do
      %Ecto.Association.NotLoaded{} -> []
      entries when is_list(entries) -> entries
      _ -> []
    end
  end

  defp delivery_decision_entry?(%{"content" => value}) when is_binary(value) and value != "",
    do: true

  defp delivery_decision_entry?(_entry), do: false

  defp publish_recovery_basis_label(recovery) do
    case recovery["decision_basis"] do
      "explicit_channel_signal" -> " explicit-signal"
      "low_confidence" -> " low-confidence"
      "revised_confident_summary" -> " confident-summary"
      _ -> ""
    end
  end

  defp publish_recovery_snapshot(work_item) do
    artifacts =
      case Map.get(work_item, :artifacts) do
        %Ecto.Association.NotLoaded{} -> []
        entries when is_list(entries) -> entries
        _ -> []
      end

    get_in(work_item.result_refs || %{}, ["delivery", "recovery"]) ||
      get_in(work_item.metadata || %{}, ["delivery_recovery"]) ||
      get_in(work_item.metadata || %{}, ["follow_up_context", "delivery_recovery"]) ||
      Enum.find_value(artifacts, fn artifact ->
        if artifact.type == "delivery_brief" do
          Map.get(artifact.payload || %{}, "delivery_recovery")
        end
      end) || %{}
  end

  defp degraded_work_item?(work_item) do
    get_in(work_item.result_refs || %{}, ["degraded"]) == true or
      get_in(work_item.metadata || %{}, ["degraded_execution"]) == true
  end

  defp work_item_side_effect_class(work_item) do
    get_in(work_item.metadata || %{}, ["side_effect_class"]) || "read_only"
  end

  defp work_item_policy_failure_label(work_item) do
    case get_in(work_item.result_refs || %{}, ["policy_failure"]) do
      %{"type" => "autonomy_level", "requested_level" => requested} ->
        "blocked autonomy #{requested}"

      %{"type" => "side_effect_class", "requested_class" => requested} ->
        "blocked effect #{requested}"

      %{"type" => "approval_stage"} ->
        "blocked pending approval"

      %{"type" => "token_budget"} ->
        "budget tokens exhausted"

      %{"type" => "time_budget"} ->
        "budget time exhausted"

      %{"type" => "delegation_depth"} ->
        "budget depth exhausted"

      %{"type" => "tool_budget"} ->
        "budget tools exhausted"

      %{"type" => "retry_budget"} ->
        "budget retries exhausted"

      %{"type" => "financial_action_locked"} ->
        "simulation only"

      _ ->
        nil
    end
  end

  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length - 1) <> "…"
    end
  end

  defp truncate_text(value, _max_length), do: value

  defp skill_tags(skill) do
    get_in(skill.metadata || %{}, ["tags"]) || []
  end

  defp skill_tools(skill) do
    get_in(skill.metadata || %{}, ["tools"]) || []
  end

  defp skill_channels(skill) do
    get_in(skill.metadata || %{}, ["channels"]) || []
  end

  defp skill_version(skill) do
    get_in(skill.metadata || %{}, ["version"])
  end

  defp skill_requires(skill) do
    get_in(skill.metadata || %{}, ["requires"]) || []
  end

  defp skill_validation_errors(skill) do
    get_in(skill.metadata || %{}, ["validation_errors"]) || []
  end

  defp skill_manifest_valid?(skill) do
    Map.get(skill.metadata || %{}, "manifest_valid", true)
  end

  defp mcp_actions(binding) do
    get_in(binding.mcp_server_config.metadata || %{}, ["actions"]) || []
  end

  defp mcp_action_count(binding), do: length(mcp_actions(binding))

  defp mcp_catalog_source(binding) do
    get_in(binding.mcp_server_config.metadata || %{}, ["action_catalog", "source"])
  end

  defp agent_tool_policy_form(agent) do
    policy = agent.tool_policy_override || Runtime.get_tool_policy() || %{}

    %{
      "workspace_list_enabled" => Map.get(policy, :workspace_list_enabled, true),
      "workspace_read_enabled" => Map.get(policy, :workspace_read_enabled, true),
      "workspace_write_enabled" => Map.get(policy, :workspace_write_enabled, false),
      "http_fetch_enabled" => Map.get(policy, :http_fetch_enabled, true),
      "browser_automation_enabled" => Map.get(policy, :browser_automation_enabled, false),
      "web_search_enabled" => Map.get(policy, :web_search_enabled, true),
      "shell_command_enabled" => Map.get(policy, :shell_command_enabled, true),
      "shell_allowlist_csv" => Map.get(policy, :shell_allowlist_csv, ""),
      "http_allowlist_csv" => Map.get(policy, :http_allowlist_csv, ""),
      "workspace_write_channels_csv" => Map.get(policy, :workspace_write_channels_csv, ""),
      "http_fetch_channels_csv" => Map.get(policy, :http_fetch_channels_csv, ""),
      "browser_automation_channels_csv" => Map.get(policy, :browser_automation_channels_csv, ""),
      "web_search_channels_csv" => Map.get(policy, :web_search_channels_csv, ""),
      "shell_command_channels_csv" => Map.get(policy, :shell_command_channels_csv, "")
    }
  end

  defp agent_control_policy_form(agent) do
    policy = agent.control_policy_override || Runtime.get_control_policy() || %{}

    %{
      "require_recent_auth_for_sensitive_actions" =>
        Map.get(policy, :require_recent_auth_for_sensitive_actions, true),
      "recent_auth_window_minutes" => Map.get(policy, :recent_auth_window_minutes, 15),
      "interactive_delivery_channels_csv" =>
        Map.get(policy, :interactive_delivery_channels_csv, ""),
      "job_delivery_channels_csv" => Map.get(policy, :job_delivery_channels_csv, ""),
      "ingest_roots_csv" => Map.get(policy, :ingest_roots_csv, "")
    }
  end

  defp normalize_checkbox_fields(params, fields) do
    Enum.reduce(fields, params, fn field, acc ->
      Map.put(acc, field, Map.get(acc, field) in ["true", "on", true])
    end)
  end

  defp enabled_label(true), do: "on"
  defp enabled_label(false), do: "off"

  defp provider_options do
    [{"Use global default", ""}] ++
      Enum.map(Runtime.list_provider_configs(), fn provider ->
        {"#{provider.name} (#{provider.model})", provider.id}
      end)
  end

  defp provider_name(nil), do: "global/mock"
  defp provider_name(provider), do: provider.name || provider.model || provider.kind

  defp fallback_summary([]), do: "none"
  defp fallback_summary(fallbacks), do: Enum.map_join(fallbacks, ", ", &provider_name/1)

  defp channel_summary([]), do: "none"
  defp channel_summary(channels), do: Enum.join(channels, ", ")

  defp bulletin_memory_labels(memory) do
    source =
      [
        bulletin_memory_value(memory, :source_file) &&
          "file #{bulletin_memory_value(memory, :source_file)}",
        bulletin_memory_value(memory, :source_channel) &&
          "channel #{bulletin_memory_value(memory, :source_channel)}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    top_breakdown =
      (bulletin_memory_value(memory, :score_breakdown) || %{})
      |> Enum.sort_by(fn {_key, value} -> -value end)
      |> Enum.take(2)
      |> Enum.map(fn {key, value} -> "#{key} #{Float.round(value, 2)}" end)

    (bulletin_memory_value(memory, :reasons) || [])
    |> Enum.take(2)
    |> Kernel.++(if(source == "", do: [], else: [source]))
    |> Kernel.++(top_breakdown)
  end

  defp bulletin_memory_value(memory, key) do
    Map.get(memory, key) || Map.get(memory, Atom.to_string(key))
  end

  defp effective_tool_summary(policy) do
    policy.tools
    |> Enum.map_join(" · ", fn tool ->
      channels =
        case tool.channels do
          :all -> "all"
          values -> channel_summary(values)
        end

      "#{tool.tool_name} #{enabled_label(tool.enabled?)} (#{channels})"
    end)
  end

  defp policy_budget_summary(policy) do
    case policy.routing.budget do
      %{warnings: warnings} when warnings != [] ->
        Enum.map_join(warnings, ", ", &to_string/1)

      %{usage: usage} when is_map(usage) ->
        "daily #{Map.get(usage, :daily_tokens) || Map.get(usage, "daily_tokens") || 0}"

      _ ->
        "steady"
    end
  end

  defp policy_workload_summary(policy) do
    case policy.routing.workload do
      %{pressure: pressure, applied?: applied?, reason: reason} ->
        "#{pressure}/#{if(applied?, do: "shifted", else: "steady")} #{reason}"

      _ ->
        "steady"
    end
  end

  defp mcp_descriptor(%{transport: "stdio", command: command}),
    do: "stdio command #{command || "unknown"}"

  defp mcp_descriptor(%{transport: "http"} = config),
    do: "HTTP #{config.url}#{config.healthcheck_path || "/health"}"

  defp mcp_descriptor(config), do: config.transport

  defp mcp_health_label(nil), do: "status unknown"
  defp mcp_health_label(status), do: "#{status.status} · #{status.detail}"
end
