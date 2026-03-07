defmodule HydraXWeb.JobsLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.ScheduledJob
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    agent = Runtime.ensure_default_agent!()
    Runtime.ensure_default_jobs!()
    filters = default_filters()

    {:ok,
     socket
     |> assign(:page_title, "Jobs")
     |> assign(:current, "jobs")
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:jobs, list_jobs(filters))
     |> assign(:runs, Runtime.recent_job_runs(20))
     |> assign(:editing_job, %ScheduledJob{})
     |> assign(
       :form,
       to_form(Runtime.change_scheduled_job(%ScheduledJob{}, default_job_attrs(agent.id)))
     )}
  end

  @impl true
  def handle_event("create", %{"scheduled_job" => params}, socket) do
    params = Map.put_new(params, "agent_id", socket.assigns.agent.id)
    params = Map.put_new(params, "next_run_at", DateTime.utc_now())
    action = if socket.assigns.editing_job.id, do: "updated", else: "saved"

    case Runtime.save_scheduled_job(socket.assigns.editing_job, params) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scheduled job #{action}")
         |> assign(:jobs, list_jobs(socket.assigns.filters))
         |> assign(:runs, Runtime.recent_job_runs(20))
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
     |> assign(:runs, Runtime.recent_job_runs(20))
     |> assign(:stats, stats())}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    job = Runtime.get_scheduled_job!(id)

    {:ok, _job} = Runtime.save_scheduled_job(job, %{enabled: !job.enabled})

    {:noreply,
     socket
     |> put_flash(:info, "Job updated")
     |> assign(:jobs, list_jobs(socket.assigns.filters))
     |> assign(:runs, Runtime.recent_job_runs(20))
     |> assign(:stats, stats())}
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

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:jobs, list_jobs(filters))}
  end

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
                    {job.kind} · every {job.interval_minutes} min
                  </div>
                  <div class="mt-1 text-xs text-[var(--hx-mute)]">
                    next {format_datetime(job.next_run_at)} · last {format_datetime(job.last_run_at)}
                  </div>
                  <div
                    :if={job.delivery_enabled}
                    class="mt-2 text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    deliver {job.delivery_channel} -> {job.delivery_target}
                  </div>
                </div>
                <span class={[
                  "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                  if(job.enabled,
                    do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                    else: "border-white/10 text-[var(--hx-mute)]"
                  )
                ]}>
                  {if job.enabled, do: "enabled", else: "paused"}
                </span>
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
              </div>
            </div>
            <div
              :if={@jobs == []}
              class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
            >
              No scheduled jobs yet.
            </div>
          </div>
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
            <.input field={@form[:interval_minutes]} type="number" label="Interval minutes" />
            <.input field={@form[:prompt]} type="textarea" label="Prompt override" />
            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
            <.input field={@form[:delivery_enabled]} type="checkbox" label="Deliver result" />
            <.input
              field={@form[:delivery_channel]}
              type="select"
              label="Delivery channel"
              options={[{"Telegram", "telegram"}]}
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
      interval_minutes: 60,
      enabled: true,
      delivery_enabled: false,
      delivery_channel: "telegram"
    }
  end

  defp default_filters do
    %{"search" => "", "kind" => "", "enabled" => ""}
  end

  defp list_jobs(filters) do
    Runtime.list_scheduled_jobs(
      limit: 50,
      kind: blank_to_nil(filters["kind"]),
      enabled: parse_enabled(filters["enabled"]),
      search: blank_to_nil(filters["search"])
    )
  end

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp run_class("success"), do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300"
  defp run_class("error"), do: "border-rose-400/20 bg-rose-400/10 text-rose-300"
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
