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
              <div class="mt-2 text-xs text-[var(--hx-mute)]">
                readiness {agent.runtime.readiness} · warmup {agent.runtime.warmup_status} · selected {provider_name(
                  agent.provider_route.provider
                )}
              </div>
              <div :if={agent.runtime.last_warm_error} class="mt-1 text-xs text-amber-200/80">
                {agent.runtime.last_warm_error}
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
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-3">
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Compaction policy
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  Soft {agent.compaction_policy.soft} · Medium {agent.compaction_policy.medium} · Hard {agent.compaction_policy.hard}
                </div>
                <% policy_form = to_form(compaction_policy_form(agent), as: :compaction_policy) %>
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
                <% routing_form = to_form(provider_routing_form(agent), as: :provider_routing) %>
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
                    Tool policy override
                  </div>
                  <span class="text-xs text-[var(--hx-mute)]">
                    {if agent.tool_policy_override, do: "override active", else: "inherits global"}
                  </span>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">
                  list {enabled_label(agent.effective_tool_policy.workspace_list_enabled)} · read {enabled_label(
                    agent.effective_tool_policy.workspace_read_enabled
                  )} · write {enabled_label(agent.effective_tool_policy.workspace_write_enabled)} · search {enabled_label(
                    agent.effective_tool_policy.web_search_enabled
                  )} · http {enabled_label(agent.effective_tool_policy.http_fetch_enabled)} · shell {enabled_label(
                    agent.effective_tool_policy.shell_command_enabled
                  )}
                </div>
                <% tool_policy_form = to_form(agent_tool_policy_form(agent), as: :agent_tool_policy) %>
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
                    label="Workspace write"
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
      |> Map.put(:provider_route, Runtime.effective_provider_route(agent.id, "channel"))
      |> Map.put(:bulletin, Runtime.agent_bulletin(agent.id))
      |> Map.put(:compaction_policy, Runtime.compaction_policy(agent.id))
      |> Map.put(:tool_policy_override, Runtime.get_agent_tool_policy(agent.id))
      |> Map.put(:effective_tool_policy, Runtime.effective_tool_policy(agent.id))
    end)
  end

  defp compaction_policy_form(agent) do
    %{
      "soft" => agent.compaction_policy.soft,
      "medium" => agent.compaction_policy.medium,
      "hard" => agent.compaction_policy.hard
    }
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

  defp agent_tool_policy_form(agent) do
    policy = agent.tool_policy_override || Runtime.get_tool_policy() || %{}

    %{
      "workspace_list_enabled" => Map.get(policy, :workspace_list_enabled, true),
      "workspace_read_enabled" => Map.get(policy, :workspace_read_enabled, true),
      "workspace_write_enabled" => Map.get(policy, :workspace_write_enabled, false),
      "http_fetch_enabled" => Map.get(policy, :http_fetch_enabled, true),
      "web_search_enabled" => Map.get(policy, :web_search_enabled, true),
      "shell_command_enabled" => Map.get(policy, :shell_command_enabled, true),
      "shell_allowlist_csv" => Map.get(policy, :shell_allowlist_csv, ""),
      "http_allowlist_csv" => Map.get(policy, :http_allowlist_csv, "")
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
end
