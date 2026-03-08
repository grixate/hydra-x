defmodule HydraXWeb.JobsLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.ScheduledJob
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(HydraX.PubSub, "jobs")
    agent = Runtime.ensure_default_agent!()
    Runtime.ensure_default_jobs!()
    filters = default_filters()
    run_filters = default_run_filters()

    {jobs, has_next} = list_jobs_paginated(filters, 1)

    {:ok,
     socket
     |> assign(:page_title, "Jobs")
     |> assign(:current, "jobs")
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> assign(:has_next, has_next)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:run_filters, run_filters)
     |> assign(:run_filter_form, to_form(run_filters, as: :run_filters))
     |> assign(:runs_export, nil)
     |> assign(:jobs, jobs)
     |> assign(:runs, list_runs(run_filters))
     |> assign(:editing_job, %ScheduledJob{})
     |> assign(
       :form,
       to_form(Runtime.change_scheduled_job(%ScheduledJob{}, default_job_attrs(agent.id)))
     )}
  end

  @impl true
  def handle_event("create", %{"scheduled_job" => params}, socket) do
    params = Map.put_new(params, "agent_id", socket.assigns.agent.id)
    action = if socket.assigns.editing_job.id, do: "updated", else: "saved"

    case Runtime.save_scheduled_job(socket.assigns.editing_job, params) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scheduled job #{action}")
         |> assign(:jobs, list_jobs(socket.assigns.filters))
         |> assign(:runs, list_runs(socket.assigns.run_filters))
         |> assign(:stats, stats())
         |> assign(:editing_job, %ScheduledJob{})
         |> assign(
           :form,
           to_form(
             Runtime.change_scheduled_job(
               %ScheduledJob{},
               default_job_attrs(socket.assigns.agent.id)
             )
           )
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("trigger", %{"id" => id}, socket) do
    job = Runtime.get_scheduled_job!(id)
    Runtime.run_scheduled_job(job)

    {:noreply,
     socket
     |> put_flash(:info, "Job executed")
     |> assign(:jobs, list_jobs(socket.assigns.filters))
     |> assign(:runs, list_runs(socket.assigns.run_filters))
     |> assign(:stats, stats())}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    job = Runtime.get_scheduled_job!(id)

    {:ok, _job} = Runtime.save_scheduled_job(job, %{enabled: !job.enabled})

    {:noreply,
     socket
     |> put_flash(:info, "Job updated")
     |> assign(:jobs, list_jobs(socket.assigns.filters))
     |> assign(:runs, list_runs(socket.assigns.run_filters))
     |> assign(:stats, stats())}
  end

  def handle_event("reset_circuit", %{"id" => id}, socket) do
    Runtime.reset_scheduled_job_circuit!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Scheduler circuit reset")
     |> assign(:jobs, list_jobs(socket.assigns.filters))
     |> assign(:runs, list_runs(socket.assigns.run_filters))
     |> assign(:stats, stats())}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Runtime.delete_scheduled_job!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Job deleted")
     |> assign(:jobs, list_jobs(socket.assigns.filters))
     |> assign(:runs, list_runs(socket.assigns.run_filters))
     |> assign(:stats, stats())
     |> assign(:editing_job, %ScheduledJob{})
     |> assign(
       :form,
       to_form(
         Runtime.change_scheduled_job(%ScheduledJob{}, default_job_attrs(socket.assigns.agent.id))
       )
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    job = Runtime.get_scheduled_job!(id)

    {:noreply,
     socket
     |> assign(:editing_job, job)
     |> assign(:form, to_form(Runtime.change_scheduled_job(job)))}
  end

  def handle_event("reset_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_job, %ScheduledJob{})
     |> assign(
       :form,
       to_form(
         Runtime.change_scheduled_job(%ScheduledJob{}, default_job_attrs(socket.assigns.agent.id))
       )
     )}
  end

  def handle_event("filter_jobs", %{"filters" => params}, socket) do
    filters =
      default_filters()
      |> Map.merge(params)

    {jobs, has_next} = list_jobs_paginated(filters, 1)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> assign(:has_next, has_next)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:jobs, jobs)}
  end

  def handle_event("filter_runs", %{"run_filters" => params}, socket) do
    filters =
      default_run_filters()
      |> Map.merge(params)

    {:noreply,
     socket
     |> assign(:run_filters, filters)
     |> assign(:run_filter_form, to_form(filters, as: :run_filters))
     |> assign(:runs, list_runs(filters))}
  end

  def handle_event("export_runs", _params, socket) do
    {:ok, export} =
      Runtime.export_job_runs(
        Path.join(HydraX.Config.install_root(), "reports"),
        run_filter_options(socket.assigns.run_filters)
      )

    {:noreply,
     socket
     |> assign(:runs_export, export)
     |> put_flash(:info, "Job run ledger exported")}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = safe_page_number(page)
    {jobs, has_next} = list_jobs_paginated(socket.assigns.filters, page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:has_next, has_next)
     |> assign(:jobs, jobs)}
  end

  @impl true
  def handle_info({:job_completed, _job_id}, socket) do
    {:noreply,
     socket
     |> assign(:jobs, list_jobs(socket.assigns.filters))
     |> assign(:runs, list_runs(socket.assigns.run_filters))
     |> assign(:stats, stats())}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Scheduled jobs</div>
          <h2 class="mt-3 font-display text-4xl">Heartbeat and prompt runs</h2>
          <div class="mt-6 space-y-3">
            <.form for={@filter_form} phx-submit="filter_jobs" class="grid gap-3 md:grid-cols-3">
              <.input field={@filter_form[:search]} label="Search" />
              <.input
                field={@filter_form[:kind]}
                type="select"
                label="Kind"
                options={[
                  {"All kinds", ""},
                  {"Heartbeat", "heartbeat"},
                  {"Prompt", "prompt"},
                  {"Backup", "backup"}
                ]}
              />
              <.input
                field={@filter_form[:enabled]}
                type="select"
                label="State"
                options={[{"All states", ""}, {"Enabled", "true"}, {"Paused", "false"}]}
              />
              <div class="md:col-span-3 pt-1">
                <.button>Filter jobs</.button>
              </div>
            </.form>
            <div
              :for={job <- @jobs}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <div class="font-display text-2xl">{job.name}</div>
                  <div class="mt-1 text-sm text-[var(--hx-mute)]">
                    {job.kind} · {schedule_summary(job)}
                  </div>
                  <div class="mt-1 text-xs text-[var(--hx-mute)]">
                    next {format_datetime(job.next_run_at)} · last {format_datetime(job.last_run_at)}
                  </div>
                  <div class="mt-1 text-xs text-[var(--hx-mute)]">
                    {execution_policy_summary(job)}
                  </div>
                  <div
                    :if={job.delivery_enabled}
                    class="mt-2 text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    deliver {job.delivery_channel} -> {job.delivery_target}
                  </div>
                  <div :if={job.last_failure_reason} class="mt-2 text-xs text-amber-200/80">
                    {failure_summary(job)}
                  </div>
                </div>
                <div class="flex flex-col items-end gap-2">
                  <span class={[
                    "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                    if(job.enabled,
                      do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                      else: "border-white/10 text-[var(--hx-mute)]"
                    )
                  ]}>
                    {if job.enabled, do: "enabled", else: "paused"}
                  </span>
                  <span
                    :if={job.circuit_state == "open"}
                    class="rounded-full border border-amber-400/20 bg-amber-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.18em] text-amber-200"
                  >
                    circuit open
                  </span>
                </div>
              </div>
              <p :if={job.prompt not in [nil, ""]} class="mt-3 text-sm text-[var(--hx-mute)]">
                {job.prompt}
              </p>
              <div class="mt-4 flex gap-3">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={job.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Edit
                </button>
                <button
                  type="button"
                  phx-click="trigger"
                  phx-value-id={job.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Run now
                </button>
                <button
                  type="button"
                  phx-click="toggle"
                  phx-value-id={job.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  {if job.enabled, do: "Pause", else: "Enable"}
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={job.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Delete
                </button>
                <button
                  :if={job.circuit_state == "open"}
                  type="button"
                  phx-click="reset_circuit"
                  phx-value-id={job.id}
                  class="btn btn-outline border-amber-400/20 bg-amber-400/10 text-amber-200 hover:bg-amber-400/20"
                >
                  Reset circuit
                </button>
              </div>
            </div>
            <div
              :if={@jobs == []}
              class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
            >
              No scheduled jobs yet.
            </div>
          </div>
          <.pagination page={@page} has_next={@has_next} />
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            {if @editing_job.id, do: "Edit job", else: "Add job"}
          </div>
          <.form for={@form} id="job-form" phx-submit="create" class="mt-6 space-y-2">
            <.input field={@form[:name]} label="Label" />
            <.input
              field={@form[:kind]}
              type="select"
              label="Kind"
              options={[{"Heartbeat", "heartbeat"}, {"Prompt", "prompt"}, {"Backup", "backup"}]}
            />
            <.input
              field={@form[:schedule_mode]}
              type="select"
              label="Schedule mode"
              options={[
                {"Interval", "interval"},
                {"Daily", "daily"},
                {"Weekly", "weekly"},
                {"Cron", "cron"}
              ]}
            />
            <.input field={@form[:interval_minutes]} type="number" label="Interval minutes" />
            <.input field={@form[:weekday_csv]} label="Weekdays (mon,tue,wed...)" />
            <.input field={@form[:run_hour]} type="number" label="Run hour (UTC)" min="0" max="23" />
            <.input
              field={@form[:run_minute]}
              type="number"
              label="Run minute (UTC)"
              min="0"
              max="59"
            />
            <.input field={@form[:cron_expression]} label="Cron expression (UTC)" />
            <.input field={@form[:prompt]} type="textarea" label="Prompt override" />
            <div class="grid gap-3 md:grid-cols-2">
              <.input
                field={@form[:active_hour_start]}
                type="number"
                label="Active hour start (UTC)"
                min="0"
                max="23"
              />
              <.input
                field={@form[:active_hour_end]}
                type="number"
                label="Active hour end (UTC)"
                min="0"
                max="23"
              />
            </div>
            <div class="grid gap-3 md:grid-cols-2">
              <.input
                field={@form[:timeout_seconds]}
                type="number"
                label="Execution timeout (seconds)"
                min="1"
              />
              <.input field={@form[:retry_limit]} type="number" label="Retries" min="0" />
            </div>
            <div class="grid gap-3 md:grid-cols-2">
              <.input
                field={@form[:retry_backoff_seconds]}
                type="number"
                label="Retry backoff (seconds)"
                min="0"
              />
              <.input
                field={@form[:pause_after_failures]}
                type="number"
                label="Open circuit after failures"
                min="0"
              />
            </div>
            <.input
              field={@form[:cooldown_minutes]}
              type="number"
              label="Circuit cooldown (minutes)"
              min="0"
            />
            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
            <.input field={@form[:delivery_enabled]} type="checkbox" label="Deliver result" />
            <.input
              field={@form[:delivery_channel]}
              type="select"
              label="Delivery channel"
              options={[
                {"Telegram", "telegram"},
                {"Discord", "discord"},
                {"Slack", "slack"}
              ]}
            />
            <.input field={@form[:delivery_target]} label="Delivery target" />
            <div class="pt-2">
              <.button>Save job</.button>
              <button
                :if={@editing_job.id}
                type="button"
                phx-click="reset_form"
                class="ml-3 inline-flex items-center rounded-2xl border border-white/10 bg-white/5 px-4 py-2 font-mono text-xs uppercase tracking-[0.18em] text-white transition hover:bg-white/10"
              >
                New job
              </button>
            </div>
          </.form>

          <div class="mt-8 text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Recent runs
          </div>
          <div class="mt-4 flex flex-wrap items-center gap-3">
            <.form
              for={@run_filter_form}
              phx-submit="filter_runs"
              class="grid flex-1 gap-3 md:grid-cols-4"
            >
              <.input
                field={@run_filter_form[:status]}
                type="select"
                label="Run status"
                options={[
                  {"All statuses", ""},
                  {"Success", "success"},
                  {"Error", "error"},
                  {"Timeout", "timeout"},
                  {"Skipped", "skipped"}
                ]}
              />
              <.input
                field={@run_filter_form[:kind]}
                type="select"
                label="Run kind"
                options={[
                  {"All kinds", ""},
                  {"Heartbeat", "heartbeat"},
                  {"Prompt", "prompt"},
                  {"Backup", "backup"}
                ]}
              />
              <.input
                field={@run_filter_form[:delivery_status]}
                type="select"
                label="Delivery"
                options={[
                  {"All delivery states", ""},
                  {"Delivered", "delivered"},
                  {"Failed", "failed"}
                ]}
              />
              <.input field={@run_filter_form[:search]} label="Search runs" />
              <div class="md:col-span-4 pt-1">
                <.button>Filter runs</.button>
              </div>
            </.form>
            <button
              type="button"
              phx-click="export_runs"
              class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
            >
              Export runs
            </button>
          </div>
          <div :if={@runs_export} class="mt-3 text-xs text-[var(--hx-mute)]">
            <div>Markdown: {@runs_export.markdown_path}</div>
            <div>JSON: {@runs_export.json_path}</div>
          </div>
          <div class="mt-4 space-y-3">
            <div
              :for={run <- @runs}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex items-center justify-between gap-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                  {run.scheduled_job && run.scheduled_job.name}
                </div>
                <span class={[
                  "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                  run_class(run.status)
                ]}>
                  {run.status}
                </span>
              </div>
              <p class="mt-3 text-sm text-[var(--hx-mute)]">{run.output || "No output captured."}</p>
              <div
                :if={delivery = delivery_status(run)}
                class="mt-3 text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]"
              >
                delivery {delivery["status"]} via {delivery["channel"]} -> {delivery["target"]}
              </div>
              <div class="mt-3 text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                {run_attempt_summary(run)}
              </div>
            </div>
            <div
              :if={@runs == []}
              class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
            >
              No job runs yet.
            </div>
          </div>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  defp default_job_attrs(agent_id) do
    %{
      agent_id: agent_id,
      name: "Workspace heartbeat",
      kind: "heartbeat",
      schedule_mode: "interval",
      interval_minutes: 60,
      weekday_csv: "mon",
      run_hour: 9,
      run_minute: 0,
      timeout_seconds: 120,
      retry_limit: 0,
      retry_backoff_seconds: 0,
      pause_after_failures: 0,
      cooldown_minutes: 0,
      enabled: true,
      delivery_enabled: false,
      delivery_channel: "telegram"
    }
  end

  defp default_filters do
    %{"search" => "", "kind" => "", "enabled" => ""}
  end

  defp default_run_filters do
    %{"search" => "", "kind" => "", "status" => "", "delivery_status" => ""}
  end

  @jobs_page_size 25

  defp list_jobs(filters) do
    Runtime.list_scheduled_jobs(
      limit: @jobs_page_size,
      kind: blank_to_nil(filters["kind"]),
      enabled: parse_enabled(filters["enabled"]),
      search: blank_to_nil(filters["search"])
    )
  end

  defp list_jobs_paginated(filters, page) do
    results =
      Runtime.list_scheduled_jobs(
        limit: @jobs_page_size + 1,
        offset: (page - 1) * @jobs_page_size,
        kind: blank_to_nil(filters["kind"]),
        enabled: parse_enabled(filters["enabled"]),
        search: blank_to_nil(filters["search"])
      )

    {Enum.take(results, @jobs_page_size), length(results) > @jobs_page_size}
  end

  defp list_runs(filters) do
    Runtime.list_job_runs(run_filter_options(filters))
  end

  defp run_filter_options(filters) do
    [
      limit: 20,
      status: blank_to_nil(filters["status"]),
      kind: blank_to_nil(filters["kind"]),
      search: blank_to_nil(filters["search"]),
      delivery_status: blank_to_nil(filters["delivery_status"])
    ]
  end

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp schedule_summary(%{schedule_mode: "daily"} = job) do
    "daily @ #{pad(job.run_hour)}:#{pad(job.run_minute)} UTC"
  end

  defp schedule_summary(%{schedule_mode: "weekly"} = job) do
    "#{job.weekday_csv || "mon"} @ #{pad(job.run_hour)}:#{pad(job.run_minute)} UTC"
  end

  defp schedule_summary(%{schedule_mode: "cron"} = job) do
    "cron #{job.cron_expression || "* * * * *"}"
  end

  defp schedule_summary(job), do: "every #{job.interval_minutes} min"

  defp run_class("success"), do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300"
  defp run_class("error"), do: "border-rose-400/20 bg-rose-400/10 text-rose-300"
  defp run_class("timeout"), do: "border-amber-400/20 bg-amber-400/10 text-amber-200"
  defp run_class("skipped"), do: "border-sky-400/20 bg-sky-400/10 text-sky-200"
  defp run_class(_), do: "border-white/10 text-[var(--hx-mute)]"

  defp delivery_status(run) do
    metadata = run.metadata || %{}
    metadata["delivery"] || metadata[:delivery]
  end

  defp parse_enabled("true"), do: true
  defp parse_enabled("false"), do: false
  defp parse_enabled(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp execution_policy_summary(job) do
    policy_parts =
      [
        "timeout #{job.timeout_seconds || 120}s",
        "retries #{job.retry_limit || 0}",
        if((job.retry_backoff_seconds || 0) > 0,
          do: "backoff #{job.retry_backoff_seconds}s"
        ),
        if(job.active_hour_start != nil and job.active_hour_end != nil,
          do: "active #{pad(job.active_hour_start)}:00-#{pad(job.active_hour_end)}:00 UTC"
        ),
        if((job.pause_after_failures || 0) > 0,
          do: "circuit #{job.pause_after_failures} failures / #{job.cooldown_minutes || 0}m"
        )
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(policy_parts, " · ")
  end

  defp run_attempt_summary(run) do
    attempts = get_in(run.metadata || %{}, ["attempt"]) || 1
    retries_used = get_in(run.metadata || %{}, ["retries_used"]) || 0

    reason =
      get_in(run.metadata || %{}, ["status_reason"]) || get_in(run.metadata || %{}, ["error"])

    ["attempt #{attempts}", "retries #{retries_used}", reason]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp failure_summary(job) do
    reason = job.last_failure_reason || "unknown"

    opened_until =
      if job.paused_until, do: " until #{format_datetime(job.paused_until)}", else: ""

    "failure #{job.consecutive_failures} · #{reason}#{opened_until}"
  end

  defp pad(nil), do: "00"
  defp pad(value) when value < 10, do: "0#{value}"
  defp pad(value), do: to_string(value)

  defp safe_page_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp safe_page_number(value) when is_integer(value) and value > 0, do: value
  defp safe_page_number(_), do: 1

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
