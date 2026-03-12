defmodule HydraXWeb.HealthLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    filters = default_filters()
    default_agent = Runtime.get_default_agent()

    {:ok,
     socket
     |> assign(:page_title, "Health")
     |> assign(:current, "health")
     |> assign(:stats, stats())
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:report_export, nil)
     |> assign(:checks, Runtime.health_snapshot())
     |> assign(:readiness_report, Runtime.readiness_report())
     |> assign(:secret_status, Runtime.secret_storage_status())
     |> assign(:memory_status, Runtime.memory_triage_status())
     |> assign(:telegram_status, Runtime.telegram_status())
     |> assign(:discord_status, Runtime.discord_status())
     |> assign(:slack_status, Runtime.slack_status())
     |> assign(:webchat_status, Runtime.webchat_status())
     |> assign(:cluster_status, Runtime.cluster_status())
     |> assign(:mcp_statuses, Runtime.mcp_statuses())
     |> assign(:agent_mcp_statuses, Runtime.agent_mcp_statuses())
     |> assign(:channel_capabilities, Runtime.channel_capabilities())
     |> assign(:safety_status, Runtime.safety_status())
     |> assign(:observability_status, Runtime.observability_status())
     |> assign(:operator_status, Runtime.operator_status())
     |> assign(:provider_status, Runtime.provider_status())
     |> assign(:tool_status, Runtime.tool_status())
     |> assign(
       :effective_policy,
       Runtime.effective_policy(default_agent && default_agent.id, process_type: "channel")
     )
     |> assign(:scheduler_status, Runtime.scheduler_status())}
  end

  @impl true
  def handle_event("filter_health", %{"filters" => params}, socket) do
    filters =
      default_filters()
      |> Map.merge(params)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:checks, filtered_checks(filters))
     |> assign(:readiness_report, filtered_readiness(filters))}
  end

  @impl true
  def handle_event("export_report", _params, socket) do
    filters = socket.assigns.filters

    {:ok, export} =
      HydraX.Report.export_snapshot(
        Path.join(HydraX.Config.install_root(), "reports"),
        only_warn: filters["check_status"] == "warn" or filters["readiness_status"] == "warn",
        required_only: filters["required_only"] == "true",
        search: blank_to_nil(filters["search"])
      )

    {:noreply,
     socket
     |> assign(:report_export, export)
     |> put_flash(:info, "Operator report exported")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="glass-panel p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Runtime health</div>
        <h2 class="mt-3 font-display text-4xl">Operational snapshot</h2>
        <div class="mt-6 flex flex-wrap items-center gap-3">
          <.button phx-click="export_report" type="button">Export operator report</.button>
          <div :if={@report_export} class="text-xs text-[var(--hx-mute)]">
            <div>Markdown: {@report_export.markdown_path}</div>
            <div>JSON: {@report_export.json_path}</div>
            <div>Bundle: {@report_export.bundle_dir}</div>
          </div>
        </div>
        <.form for={@filter_form} phx-submit="filter_health" class="mt-6 grid gap-3 lg:grid-cols-4">
          <.input field={@filter_form[:search]} label="Search" />
          <.input
            field={@filter_form[:check_status]}
            type="select"
            label="Health status"
            options={[{"All", ""}, {"Warn", "warn"}, {"Ok", "ok"}]}
          />
          <.input
            field={@filter_form[:readiness_status]}
            type="select"
            label="Readiness status"
            options={[{"All", ""}, {"Warn", "warn"}, {"Ok", "ok"}]}
          />
          <.input
            field={@filter_form[:required_only]}
            type="select"
            label="Readiness scope"
            options={[{"All items", "false"}, {"Required only", "true"}]}
          />
          <div class="lg:col-span-4 pt-1">
            <.button>Filter health</.button>
          </div>
        </.form>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={check <- @checks}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {check.name}
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                if(check.status == :ok,
                  do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                  else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                )
              ]}>
                {check.status}
              </span>
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">{check.detail}</p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Preview readiness</div>
        <h2 class="mt-3 font-display text-4xl">Launch blockers and recommendations</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-4">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Total items
            </div>
            <div class="mt-3 font-display text-4xl">{@readiness_report.counts.total}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Warnings
            </div>
            <div class="mt-3 font-display text-4xl">{@readiness_report.counts.warn}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Required blockers
            </div>
            <div class="mt-3 font-display text-4xl">{@readiness_report.counts.required_warn}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Recommended fixes
            </div>
            <div class="mt-3 font-display text-4xl">
              {@readiness_report.counts.recommended_warn}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Next steps
            </div>
            <div class="mt-3 space-y-2">
              <p :if={@readiness_report.next_steps == []} class="text-sm text-[var(--hx-mute)]">
                No readiness actions are pending.
              </p>
              <p
                :for={step <- @readiness_report.next_steps}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3 text-sm text-[var(--hx-mute)]"
              >
                {step}
              </p>
            </div>
          </article>
        </div>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={item <- @readiness_report.items}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {item.label}
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                if(item.status == :ok,
                  do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                  else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                )
              ]}>
                {item.status}
              </span>
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">{item.detail}</p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              {if item.required, do: "required", else: "recommended"}
            </p>
          </article>
          <article
            :if={@readiness_report.items == []}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)] lg:col-span-2"
          >
            No readiness items match the current filter.
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Memory triage</div>
        <h2 class="mt-3 font-display text-4xl">Conflict review queue</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-3">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Active
            </div>
            <div class="mt-3 font-display text-4xl">
              {Map.get(@memory_status.counts, "active", 0)}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Conflicted
            </div>
            <div class="mt-3 font-display text-4xl">
              {Map.get(@memory_status.counts, "conflicted", 0)}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Merged/Superseded
            </div>
            <div class="mt-3 font-display text-4xl">
              {Map.get(@memory_status.counts, "merged", 0) +
                Map.get(@memory_status.counts, "superseded", 0)}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Embedding backend
            </div>
            <div class="mt-3 font-display text-2xl">{@memory_status.embedding.active_backend}</div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              model {@memory_status.embedding.active_model}
            </p>
            <p :if={@memory_status.embedding.degraded?} class="mt-2 text-xs text-amber-200">
              configured {@memory_status.embedding.configured_backend} is degraded; fallback active
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Embedded
            </div>
            <div class="mt-3 font-display text-4xl">{@memory_status.embedding.embedded_count}</div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              missing {@memory_status.embedding.unembedded_count} · stale {@memory_status.embedding.stale_count}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Fallback writes
            </div>
            <div class="mt-3 font-display text-4xl">{@memory_status.embedding.fallback_count}</div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              {if @memory_status.embedding.fallback_enabled?,
                do: "fallback enabled",
                else: "fallback disabled"}
            </p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Secrets</div>
        <h2 class="mt-3 font-display text-4xl">Secret posture</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-4">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Posture
            </div>
            <div class="mt-3 font-display text-3xl">{@secret_status.posture}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Protected
            </div>
            <div class="mt-3 font-display text-3xl">
              {@secret_status.protected_records}/{@secret_status.total_records}
            </div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              coverage {@secret_status.coverage_percent}% · key source {@secret_status.key_source}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Encrypted / env
            </div>
            <div class="mt-3 font-display text-3xl">
              {@secret_status.encrypted_records}/{@secret_status.env_backed_records}
            </div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              encrypted / env-backed
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Unresolved / plaintext
            </div>
            <div class="mt-3 font-display text-3xl">
              {@secret_status.unresolved_env_records}/{@secret_status.plaintext_records}
            </div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              unresolved env / plaintext
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Scope coverage
            </div>
            <div class="mt-3 space-y-2">
              <div
                :for={scope <- @secret_status.scopes}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">{scope.scope}</div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {scope.protected_records}/{scope.total_records} protected
                  </div>
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  encrypted {scope.encrypted_records} · env-backed {scope.env_backed_records} · unresolved env {scope.unresolved_env_records} · plaintext {scope.plaintext_records}
                </div>
              </div>
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Current issues
            </div>
            <div class="mt-3 space-y-2">
              <p :if={@secret_status.issues == []} class="text-sm text-[var(--hx-mute)]">
                No secret storage issues detected.
              </p>
              <p
                :for={issue <- @secret_status.issues}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3 text-sm text-[var(--hx-mute)]"
              >
                {issue}
              </p>
            </div>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Telegram</div>
        <h2 class="mt-3 font-display text-4xl">Channel readiness</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Webhook URL
            </div>
            <p class="mt-3 break-all text-sm text-[var(--hx-accent)]">
              {@telegram_status.webhook_url}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Binding
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {(@telegram_status.bot_username && "@#{@telegram_status.bot_username}") ||
                "unconfigured"}
              {if @telegram_status.default_agent_name,
                do: " -> #{@telegram_status.default_agent_name}",
                else: ""}
            </p>
            <p :if={@telegram_status.registered_at} class="mt-2 text-xs text-[var(--hx-mute)]">
              Registered at {Calendar.strftime(
                @telegram_status.registered_at,
                "%Y-%m-%d %H:%M:%S UTC"
              )}
            </p>
            <p :if={@telegram_status.last_checked_at} class="mt-2 text-xs text-[var(--hx-mute)]">
              Last checked at {Calendar.strftime(
                @telegram_status.last_checked_at,
                "%Y-%m-%d %H:%M:%S UTC"
              )}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              Pending updates: {@telegram_status.pending_update_count}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              Retryable failed deliveries: {@telegram_status.retryable_count}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              dead letter {@telegram_status.dead_letter_count || 0} · multipart {@telegram_status.multipart_failure_count ||
                0} ·
              attachment failures {@telegram_status.attachment_failure_count || 0} · streaming {@telegram_status.streaming_count ||
                0}
            </p>
            <p :if={@telegram_status.last_error} class="mt-2 text-xs text-amber-200">
              Last Telegram error: {@telegram_status.last_error}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Recent Telegram delivery failures
            </div>
            <div class="mt-3 space-y-2">
              <p
                :if={@telegram_status.recent_failures == []}
                class="text-sm text-[var(--hx-mute)]"
              >
                No recent Telegram delivery failures.
              </p>
              <div
                :for={failure <- @telegram_status.recent_failures}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">
                    ##{failure.id} {failure.title}
                  </div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {format_datetime(failure.updated_at)}
                  </div>
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  {failure_delivery_summary(failure)}
                </div>
              </div>
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Active Telegram streams
            </div>
            <div class="mt-3 space-y-2">
              <p
                :if={@telegram_status.recent_streaming == []}
                class="text-sm text-[var(--hx-mute)]"
              >
                No active Telegram streams.
              </p>
              <div
                :for={stream <- @telegram_status.recent_streaming}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">
                    ##{stream.id} {stream.title}
                  </div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {format_datetime(stream.updated_at)}
                  </div>
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  {failure_delivery_summary(stream)}
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Provider route</div>
        <h2 class="mt-3 font-display text-4xl">LLM adapter capabilities</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Selected route
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@provider_status.name} · {@provider_status.kind}
              <span :if={@provider_status.model}>
                 ·                     {@provider_status.model}
              </span>
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              source {@provider_status.route_source} · readiness {@provider_status.readiness} · warmup {@provider_status.warmup_status}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Capabilities
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {provider_capability_summary(@provider_status.capabilities)}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              fallbacks {@provider_status.fallback_count}
            </p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Cluster posture</div>
        <h2 class="mt-3 font-display text-4xl">Node-aware readiness</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Mode
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@cluster_status.mode} · node {@cluster_status.node_id}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              visible nodes {@cluster_status.node_count} · leader {@cluster_status.leader_node ||
                "none"}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Persistence posture
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@cluster_status.persistence} · {if @cluster_status.multi_node_ready,
                do: "multi-node ready",
                else: "single-node only"}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              {@cluster_status.persistence_backend} · {@cluster_status.persistence_target ||
                "no persistence target"}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              {@cluster_status.detail}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Coordination mode
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@observability_status.coordination.mode} · scheduler owner {@observability_status.coordination.scheduler_owner ||
                "none"}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              active leases {@observability_status.coordination.lease_count} · backend {@observability_status.coordination.backend}
            </p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">MCP servers</div>
        <h2 class="mt-3 font-display text-4xl">Registry health</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={status <- @mcp_statuses}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {status.name}
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                if(status.status == :ok,
                  do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                  else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                )
              ]}>
                {status.status}
              </span>
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">{status.transport} · {status.detail}</p>
          </article>
          <article
            :if={@mcp_statuses == []}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)] lg:col-span-2"
          >
            No MCP servers configured.
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Agent MCP</div>
        <h2 class="mt-3 font-display text-4xl">Bound integrations by agent</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={status <- @agent_mcp_statuses}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {status.agent_slug}
              </div>
              <span class="rounded-full border border-white/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {status.enabled_bindings}/{status.total_bindings} enabled
              </span>
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {status.agent_name} · healthy bindings {status.healthy_bindings}
            </p>
            <div class="mt-3 space-y-2">
              <p :if={status.bindings == []} class="text-xs text-[var(--hx-mute)]">
                No MCP bindings for this agent.
              </p>
              <div
                :for={binding <- status.bindings}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">{binding.server_name}</div>
                  <div class={[
                    "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                    if(binding.status == :ok,
                      do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                      else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                    )
                  ]}>
                    {binding.status}
                  </div>
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  {binding.transport} · {if(binding.enabled, do: "enabled", else: "disabled")} · {binding.detail}
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
          Discord + Slack + Webchat
        </div>
        <h2 class="mt-3 font-display text-4xl">Additional channel readiness</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article
            :for={status <- [@discord_status, @slack_status, @webchat_status]}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex items-center justify-between gap-4">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {status.channel}
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                if(status.configured and status.enabled,
                  do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                  else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                )
              ]}>
                {if(status.configured and status.enabled, do: "ready", else: "pending")}
              </span>
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {if status.configured, do: "configured", else: "not configured"}
              {if status.default_agent_name, do: " -> #{status.default_agent_name}", else: ""}
            </p>
            <p :if={status.binding} class="mt-2 break-all text-xs text-[var(--hx-mute)]">
              binding: {status.binding}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              capabilities: {capability_summary(@channel_capabilities[status.channel])}
            </p>
            <p :if={channel_policy_summary(status)} class="mt-2 text-xs text-[var(--hx-mute)]">
              policy: {channel_policy_summary(status)}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              retryable {status.retryable_count || 0} · dead letter {status.dead_letter_count || 0} ·
              multipart {status.multipart_failure_count || 0} ·
              attachment failures {status.attachment_failure_count || 0} · streaming {status.streaming_count ||
                0}
            </p>
            <div class="mt-3 space-y-2">
              <p
                :if={status.recent_failures == []}
                class="text-xs text-[var(--hx-mute)]"
              >
                No recent delivery failures.
              </p>
              <div
                :for={failure <- status.recent_failures}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">##{failure.id} {failure.title}</div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {format_datetime(failure.updated_at)}
                  </div>
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  {failure_delivery_summary(failure)}
                </div>
              </div>
              <div :if={status.recent_streaming != []} class="pt-1">
                <div class="text-[0.7rem] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Active streams
                </div>
                <div class="mt-2 space-y-2">
                  <div
                    :for={stream <- status.recent_streaming}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="text-sm text-[var(--hx-accent)]">
                        ##{stream.id} {stream.title}
                      </div>
                      <div class="text-xs text-[var(--hx-mute)]">
                        {format_datetime(stream.updated_at)}
                      </div>
                    </div>
                    <div class="mt-2 text-xs text-[var(--hx-mute)]">
                      {failure_delivery_summary(stream)}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Operator auth</div>
        <h2 class="mt-3 font-display text-4xl">Control-plane lock state</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Status
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {if @operator_status.configured,
                do: "Operator password is configured",
                else: "Control plane is open until a password is set"}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Rotation
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {if @operator_status.last_rotated_at,
                do: Calendar.strftime(@operator_status.last_rotated_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "not set"}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Password age
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {if @operator_status.password_age_days != nil,
                do: "#{@operator_status.password_age_days} days",
                else: "not set"}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Session policy
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              Max {div(@operator_status.session_max_age_seconds, 3600)}h, idle {div(
                @operator_status.idle_timeout_seconds,
                60
              )}m, recent auth {div(@operator_status.recent_auth_window_seconds, 60)}m
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Login throttle
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@operator_status.login_max_attempts} attempts per {@operator_status.login_window_seconds}s window
              <span :if={@operator_status.blocked_login_ips > 0}>
                · blocked IPs {@operator_status.blocked_login_ips}
              </span>
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Last sign-in
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {format_datetime(@operator_status.last_login_at)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Last failure
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {format_datetime(@operator_status.last_login_failure_at)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Last session expiry
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {format_datetime(@operator_status.last_session_expired_at)}
            </p>
            <p
              :if={@operator_status.last_session_expired_reason}
              class="mt-2 text-xs text-[var(--hx-mute)]"
            >
              reason {@operator_status.last_session_expired_reason}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Last reauth block
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {format_datetime(@operator_status.last_sensitive_action_block_at)}
            </p>
          </article>
        </div>
        <div class="mt-6 grid gap-3 lg:grid-cols-4">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Sign-ins (24h)
            </div>
            <div class="mt-3 font-display text-4xl">
              {@operator_status.recent_login_success_count}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Failures (24h)
            </div>
            <div class="mt-3 font-display text-4xl">
              {@operator_status.recent_login_failure_count}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Reauth blocks
            </div>
            <div class="mt-3 font-display text-4xl">{@operator_status.recent_reauth_block_count}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Session expiries
            </div>
            <div class="mt-3 font-display text-4xl">
              {@operator_status.recent_session_expiry_count}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Recent auth audit
            </div>
            <div class="mt-3 space-y-2">
              <p :if={@operator_status.recent_events == []} class="text-sm text-[var(--hx-mute)]">
                No recent auth audit events.
              </p>
              <div
                :for={event <- @operator_status.recent_events}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">{event.message}</div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {format_datetime(event.inserted_at)}
                  </div>
                </div>
                <div class="mt-2 text-xs text-[var(--hx-mute)]">
                  level {event.level}
                  <span :if={event.expired_by}> · expiry          {event.expired_by}</span>
                  <span :if={event.reauth?}> · reauth</span>
                  <span :if={event.ip}> · ip          {event.ip}</span>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Effective policy</div>
        <h2 class="mt-3 font-display text-4xl">Unified decision surface</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-4">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Recent auth
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {if @effective_policy.auth.recent_auth_required, do: "required", else: "optional"} within {@effective_policy.auth.recent_auth_window_minutes}m
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Interactive delivery
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {channel_summary(@effective_policy.deliveries.interactive_channels)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Job delivery
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {channel_summary(@effective_policy.deliveries.job_channels)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Ingest roots
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {channel_summary(@effective_policy.ingest.roots)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Provider route
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@effective_policy.routing.provider_name} via {@effective_policy.routing.source}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              fallbacks {channel_summary(@effective_policy.routing.fallback_names)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Budget routing
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {policy_budget_summary(@effective_policy)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Workload routing
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {policy_workload_summary(@effective_policy)}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Tool access matrix
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {effective_tool_summary(@effective_policy)}
            </p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Guarded tools</div>
        <h2 class="mt-3 font-display text-4xl">Execution policy</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-3">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Workspace listing
            </div>
            <div class="mt-3 font-display text-4xl">
              {if @tool_status.workspace_list_enabled, do: "on", else: "off"}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Workspace guard
            </div>
            <div class="mt-3 font-display text-4xl">
              {if @tool_status.workspace_guard, do: "on", else: "off"}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Workspace writes
            </div>
            <div class="mt-3 font-display text-4xl">
              {if @tool_status.workspace_write_enabled, do: "on", else: "off"}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              URL guard
            </div>
            <div class="mt-3 font-display text-4xl">
              {if @tool_status.url_guard, do: "on", else: "off"}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Web search
            </div>
            <div class="mt-3 font-display text-4xl">
              {if @tool_status.web_search_enabled, do: "on", else: "off"}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Shell execution
            </div>
            <div class="mt-3 font-display text-4xl">
              {if @tool_status.shell_command_enabled, do: "on", else: "off"}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-3">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Shell allowlist
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {Enum.join(@tool_status.shell_allowlist, ", ")}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-3">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              HTTP allowlist
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {if @tool_status.http_allowlist == [],
                do: "all public hosts allowed",
                else: Enum.join(@tool_status.http_allowlist, ", ")}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-3">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Tool channel policy
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              write {channel_summary(@tool_status.workspace_write_channels)} ·
              http {channel_summary(@tool_status.http_fetch_channels)} ·
              search {channel_summary(@tool_status.web_search_channels)} ·
              shell {channel_summary(@tool_status.shell_command_channels)}
            </p>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Scheduler</div>
        <h2 class="mt-3 font-display text-4xl">Heartbeat and job execution</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-5">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Configured jobs
            </div>
            <div class="mt-3 font-display text-4xl">{length(@scheduler_status.jobs)}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Recent runs
            </div>
            <div class="mt-3 font-display text-4xl">{length(@scheduler_status.runs)}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Latest run
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              {@scheduler_status.runs |> List.first() |> then(&(&1 && &1.status)) || "none"}
            </p>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Open circuits
            </div>
            <div class="mt-3 font-display text-4xl">{length(@scheduler_status.open_circuits)}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Skipped runs
            </div>
            <div class="mt-3 font-display text-4xl">{length(@scheduler_status.skipped_runs)}</div>
          </article>
        </div>
        <div :if={@scheduler_status.open_circuits != []} class="mt-4 space-y-2">
          <div class="font-mono text-xs uppercase tracking-[0.18em] text-amber-200">
            Open scheduler circuits
          </div>
          <div
            :for={job <- @scheduler_status.open_circuits}
            class="rounded-2xl border border-amber-400/20 bg-amber-400/10 px-4 py-3 text-sm text-amber-100"
          >
            {job.name} · failures {job.consecutive_failures} · {job.last_failure_reason || "unknown"} · {if job.paused_until,
              do: "paused until #{Calendar.strftime(job.paused_until, "%Y-%m-%d %H:%M UTC")}",
              else: "manual reset required"}
          </div>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Observability</div>
        <h2 class="mt-3 font-display text-4xl">Runtime counters</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-5">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Provider requests
            </div>
            <div class="mt-3 font-display text-4xl">
              {@observability_status.telemetry_summary.provider.total}
            </div>
            <div class="mt-2 text-xs text-[var(--hx-mute)]">
              ok {@observability_status.telemetry_summary.provider.success} · error {@observability_status.telemetry_summary.provider.error}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Budget events
            </div>
            <div class="mt-3 font-display text-4xl">
              {@observability_status.telemetry_summary.budget.total}
            </div>
            <div class="mt-2 text-xs text-[var(--hx-mute)]">
              warn {@observability_status.telemetry_summary.budget.warn} · error {@observability_status.telemetry_summary.budget.error}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Tool executions
            </div>
            <div class="mt-3 font-display text-4xl">
              {@observability_status.telemetry_summary.tool.total}
            </div>
            <div class="mt-2 text-xs text-[var(--hx-mute)]">
              ok {@observability_status.telemetry_summary.tool.success} · error {@observability_status.telemetry_summary.tool.error}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Gateway delivery
            </div>
            <div class="mt-3 font-display text-4xl">
              {@observability_status.telemetry_summary.gateway.total}
            </div>
            <div class="mt-2 text-xs text-[var(--hx-mute)]">
              ok {@observability_status.telemetry_summary.gateway.success} · error {@observability_status.telemetry_summary.gateway.error}
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Scheduler counters
            </div>
            <div class="mt-3 font-display text-4xl">
              {@observability_status.telemetry_summary.scheduler.total}
            </div>
            <div class="mt-2 text-xs text-[var(--hx-mute)]">
              ok {@observability_status.telemetry_summary.scheduler.success} · error {@observability_status.telemetry_summary.scheduler.error}
            </div>
          </article>
        </div>
        <div class="mt-6 grid gap-3 lg:grid-cols-2">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Recent telemetry events
            </div>
            <div class="mt-3 space-y-2">
              <p
                :if={@observability_status.telemetry.recent_events == []}
                class="text-sm text-[var(--hx-mute)]"
              >
                No telemetry events captured yet.
              </p>
              <div
                :for={event <- @observability_status.telemetry.recent_events}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    {event.namespace} · {event.bucket}
                  </div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {format_datetime(event.observed_at)}
                  </div>
                </div>
                <div class="mt-2 text-sm text-[var(--hx-mute)]">status {event.status}</div>
              </div>
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              System alarms
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              Persistence: {@observability_status.system.persistence.backend} · {@observability_status.system.persistence.target ||
                "not configured"}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              Backup mode: {@observability_status.system.persistence.backup_mode}
            </p>
            <div class="mt-3 space-y-2">
              <p
                :if={@observability_status.system.alarms == []}
                class="text-sm text-[var(--hx-mute)]"
              >
                No active OTP alarms.
              </p>
              <p
                :for={alarm <- @observability_status.system.alarms}
                class="text-sm text-amber-200"
              >
                {alarm}
              </p>
            </div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 lg:col-span-2">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Backup inventory
            </div>
            <p class="mt-3 text-sm text-[var(--hx-mute)]">
              Root: {@observability_status.backups.root}
            </p>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              verified {@observability_status.backups.verified_count} · failed {@observability_status.backups.verification_failed_count} · pending {@observability_status.backups.unverified_count}
            </p>
            <div class="mt-3 space-y-2">
              <p
                :if={@observability_status.backups.recent_backups == []}
                class="text-sm text-[var(--hx-mute)]"
              >
                No backup manifests found.
              </p>
              <div
                :for={backup <- @observability_status.backups.recent_backups}
                class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
              >
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div class="text-sm text-[var(--hx-accent)]">{backup["archive_path"]}</div>
                  <div class="text-xs text-[var(--hx-mute)]">
                    {backup_archive_label(backup)}
                  </div>
                </div>
                <div class="mt-1 text-xs text-[var(--hx-mute)]">
                  entries: {backup["entry_count"]} · size {backup["archive_size_bytes"] || 0} · created {backup[
                    "created_at"
                  ]}
                </div>
                <div :if={(backup["missing_entries"] || []) != []} class="mt-1 text-xs text-amber-200">
                  missing {Enum.join(backup["missing_entries"], ", ")}
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section class="glass-panel mt-6 p-6">
        <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Safety ledger</div>
        <h2 class="mt-3 font-display text-4xl">Recent runtime events</h2>
        <div class="mt-6 grid gap-3 lg:grid-cols-3">
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Errors
            </div>
            <div class="mt-3 font-display text-4xl">{@safety_status.counts.error}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Warnings
            </div>
            <div class="mt-3 font-display text-4xl">{@safety_status.counts.warn}</div>
          </article>
          <article class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Info
            </div>
            <div class="mt-3 font-display text-4xl">{@safety_status.counts.info}</div>
          </article>
        </div>

        <div class="mt-6 space-y-3">
          <div
            :for={event <- @safety_status.recent_events}
            class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                  {event.category}
                </div>
                <p class="mt-2 text-sm">{event.message}</p>
              </div>
              <span class={[
                "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                level_class(event.level)
              ]}>
                {event.level}
              </span>
            </div>
            <p class="mt-2 text-xs text-[var(--hx-mute)]">
              {event.agent && event.agent.name}
              {if event.conversation,
                do: " · #{event.conversation.title || event.conversation.channel}",
                else: ""}
            </p>
          </div>
          <div
            :if={@safety_status.recent_events == []}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
          >
            No recent safety events.
          </div>
        </div>
      </section>
    </AppShell.shell>
    """
  end

  defp level_class("error"), do: "border-rose-400/20 bg-rose-400/10 text-rose-300"
  defp level_class("warn"), do: "border-amber-400/20 bg-amber-400/10 text-amber-300"
  defp level_class(_), do: "border-white/10 bg-black/10 text-[var(--hx-mute)]"

  defp filtered_checks(filters) do
    Runtime.health_snapshot(
      status: blank_to_nil(filters["check_status"]),
      search: blank_to_nil(filters["search"])
    )
  end

  defp filtered_readiness(filters) do
    Runtime.readiness_report(
      status: blank_to_nil(filters["readiness_status"]),
      search: blank_to_nil(filters["search"]),
      required_only: filters["required_only"] == "true"
    )
  end

  defp default_filters do
    %{
      "search" => "",
      "check_status" => "",
      "readiness_status" => "",
      "required_only" => "false"
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_datetime(nil), do: "unknown"
  defp format_datetime(value) when is_binary(value), do: value
  defp format_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  defp channel_summary([]), do: "none"
  defp channel_summary(channels), do: Enum.join(channels, ", ")

  defp effective_tool_summary(policy) do
    policy.tools
    |> Enum.map_join(" · ", fn tool ->
      channels =
        case tool.channels do
          :all -> "all"
          values -> channel_summary(values)
        end

      "#{tool.tool_name} #{if(tool.enabled?, do: "on", else: "off")} (#{channels})"
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

  defp provider_capability_summary(capabilities) do
    capabilities
    |> Enum.filter(fn {_key, value} -> value end)
    |> Enum.map(fn {key, _value} -> key |> to_string() |> String.replace("_", "-") end)
    |> case do
      [] -> "none"
      values -> Enum.join(values, " · ")
    end
  end

  defp capability_summary(nil), do: "unknown"

  defp capability_summary(capabilities) do
    [
      if(capabilities[:threads], do: "threads", else: "no-threads"),
      if(capabilities[:attachments], do: "attachments", else: "no-attachments"),
      if(capabilities[:rich_formatting], do: "rich", else: "plain"),
      if(capabilities[:streaming], do: "streaming", else: "non-streaming"),
      streaming_transport_label(capabilities)
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" · ")
  end

  defp streaming_transport_label(nil), do: nil

  defp streaming_transport_label(capabilities) do
    case capabilities[:stream_transport] || capabilities["stream_transport"] do
      nil -> nil
      value -> "transport #{value}"
    end
  end

  defp channel_policy_summary(%{channel: "webchat", configured: false}), do: nil

  defp channel_policy_summary(%{channel: "webchat"} = status) do
    identity =
      if Map.get(status, :allow_anonymous_messages, true) do
        "anonymous ok"
      else
        "identity required"
      end

    attachments =
      if Map.get(status, :attachments_enabled, false) do
        "attachments #{Map.get(status, :max_attachment_count, 0)}x#{Map.get(status, :max_attachment_size_kb, 0)}KB"
      else
        "attachments disabled"
      end

    "#{identity} · max #{Map.get(status, :session_max_age_minutes, 0)}m · idle #{Map.get(status, :session_idle_timeout_minutes, 0)}m · #{attachments}"
  end

  defp channel_policy_summary(_status), do: nil

  defp backup_archive_label(backup) do
    cond do
      not backup["archive_exists"] ->
        "archive missing"

      backup["verified"] == true ->
        "archive verified"

      backup["verified"] == false ->
        "verify failed"

      true ->
        "archive present"
    end
  end

  defp failure_delivery_summary(conversation) do
    delivery =
      case conversation do
        %{status: status} = failure when is_binary(status) ->
          %{
            "status" => failure.status,
            "reason" => failure.reason,
            "retry_count" => failure.retry_count,
            "next_retry_at" => failure.next_retry_at,
            "dead_lettered_at" => failure.dead_lettered_at,
            "chunk_count" => failure.chunk_count,
            "formatted_payload" => Map.get(failure, :formatted_payload, %{}),
            "provider_message_ids_count" => failure.provider_message_ids_count,
            "attachment_count" => failure.attachment_count,
            "transport" => Map.get(failure, :transport),
            "transport_topic" => Map.get(failure, :transport_topic),
            "reply_context" => failure.reply_context || %{}
          }

        failure ->
          last_delivery(failure)
      end

    payload = delivery["formatted_payload"] || %{}

    provider_message_ids =
      delivery["provider_message_ids"] ||
        get_in(delivery, ["metadata", "provider_message_ids"]) || []

    provider_message_ids_count =
      delivery["provider_message_ids_count"] || length(provider_message_ids)

    [
      delivery["status"] || "unknown",
      retry_count_label(delivery["retry_count"]),
      delivery["reason"],
      next_retry_label(delivery["next_retry_at"]),
      dead_letter_label(delivery["dead_lettered_at"]),
      if(provider_message_ids_count > 0, do: "msg ids #{provider_message_ids_count}"),
      attachment_count_label(delivery["attachment_count"]),
      delivery_transport_summary(delivery),
      delivery_context_summary(delivery),
      chunk_count_summary(payload, delivery["chunk_count"])
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" · ")
  end

  defp delivery_transport_summary(delivery) do
    transport =
      get_in(delivery, ["metadata", "transport"]) ||
        delivery["transport"] ||
        (get_in(delivery, ["metadata", "transport_error"]) && "transport error")

    transport_topic =
      get_in(delivery, ["metadata", "transport_topic"]) || delivery["transport_topic"]

    [
      transport && "transport #{transport}",
      transport_topic && "topic #{transport_topic}"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      labels -> Enum.join(labels, " · ")
    end
  end

  defp delivery_context_summary(delivery) do
    reply_context = delivery["reply_context"] || %{}

    [
      reply_context["reply_to_message_id"] && "reply #{reply_context["reply_to_message_id"]}",
      reply_context["thread_ts"] && "thread #{reply_context["thread_ts"]}",
      reply_context["source_message_id"] && "source #{reply_context["source_message_id"]}"
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      labels -> Enum.join(labels, " · ")
    end
  end

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery] || %{}
  end

  defp chunk_count_summary(payload, fallback) when is_map(payload) do
    case payload["chunk_count"] || fallback do
      count when is_integer(count) and count > 1 -> "chunks #{count}"
      _ -> nil
    end
  end

  defp retry_count_label(count) when is_integer(count) and count > 0, do: "retry #{count}"
  defp retry_count_label(_count), do: nil

  defp next_retry_label(%DateTime{} = value), do: "next retry #{format_datetime(value)}"
  defp next_retry_label(_value), do: nil

  defp dead_letter_label(%DateTime{} = value), do: "dead letter #{format_datetime(value)}"
  defp dead_letter_label(_value), do: nil

  defp attachment_count_label(count) when is_integer(count) and count > 0,
    do: "attachments #{count}"

  defp attachment_count_label(_count), do: nil

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false

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
