defmodule HydraXWeb.JobsLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.ScheduledJob
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    agent = Runtime.ensure_default_agent!()

    {:ok,
     socket
     |> assign(:page_title, "Jobs")
     |> assign(:current, "jobs")
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:jobs, Runtime.list_scheduled_jobs(limit: 50))
     |> assign(:runs, Runtime.recent_job_runs(20))
     |> assign(
       :form,
       to_form(Runtime.change_scheduled_job(%ScheduledJob{}, default_job_attrs(agent.id)))
     )}
  end

  @impl true
  def handle_event("create", %{"scheduled_job" => params}, socket) do
    params = Map.put_new(params, "agent_id", socket.assigns.agent.id)
    params = Map.put_new(params, "next_run_at", DateTime.utc_now())

    case Runtime.save_scheduled_job(params) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scheduled job saved")
         |> assign(:jobs, Runtime.list_scheduled_jobs(limit: 50))
         |> assign(:runs, Runtime.recent_job_runs(20))
         |> assign(:stats, stats())
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
     |> assign(:jobs, Runtime.list_scheduled_jobs(limit: 50))
     |> assign(:runs, Runtime.recent_job_runs(20))
     |> assign(:stats, stats())}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    job = Runtime.get_scheduled_job!(id)

    {:ok, _job} = Runtime.save_scheduled_job(job, %{enabled: !job.enabled})

    {:noreply,
     socket
     |> put_flash(:info, "Job updated")
     |> assign(:jobs, Runtime.list_scheduled_jobs(limit: 50))
     |> assign(:runs, Runtime.recent_job_runs(20))
     |> assign(:stats, stats())}
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
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Add job</div>
          <.form for={@form} id="job-form" phx-submit="create" class="mt-6 space-y-2">
            <.input field={@form[:name]} label="Label" />
            <.input
              field={@form[:kind]}
              type="select"
              label="Kind"
              options={[{"Heartbeat", "heartbeat"}, {"Prompt", "prompt"}]}
            />
            <.input field={@form[:interval_minutes]} type="number" label="Interval minutes" />
            <.input field={@form[:prompt]} type="textarea" label="Prompt override" />
            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
            <div class="pt-2">
              <.button>Save job</.button>
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
      enabled: true
    }
  end

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp run_class("success"), do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300"
  defp run_class("error"), do: "border-rose-400/20 bg-rose-400/10 text-rose-300"
  defp run_class(_), do: "border-white/10 text-[var(--hx-mute)]"

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
