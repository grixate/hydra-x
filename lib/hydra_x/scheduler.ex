defmodule HydraX.Scheduler do
  @moduledoc false
  use GenServer

  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.Runtime

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Run retention cleanup once per day (in milliseconds)
  @retention_interval_ms 24 * 60 * 60 * 1000
  @retention_days 30

  @impl true
  def init(_opts) do
    schedule_poll()
    schedule_retention()
    {:ok, %{running_jobs: MapSet.new()}}
  end

  @impl true
  def handle_info(:poll, state) do
    # In cluster mode, only the leader node runs scheduled jobs
    if Cluster.leader?() do
      do_poll(state)
    else
      schedule_poll()
      {:noreply, state}
    end
  end

  def handle_info({:job_finished, job_id}, state) do
    {:noreply, %{state | running_jobs: MapSet.delete(state.running_jobs, job_id)}}
  end

  def handle_info(:retention_cleanup, state) do
    Runtime.delete_old_job_runs(@retention_days)
    schedule_retention()
    {:noreply, state}
  end

  # -- Private --

  defp do_poll(state) do
    due_jobs = Runtime.list_due_scheduled_jobs(DateTime.utc_now())

    # Skip jobs that are already in-flight
    new_jobs = Enum.reject(due_jobs, fn job -> MapSet.member?(state.running_jobs, job.id) end)

    scheduler_pid = self()

    running_ids =
      Enum.reduce(new_jobs, state.running_jobs, fn job, acc ->
        {:ok, _pid} =
          Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
            try do
              Runtime.run_scheduled_job(job)
            after
              send(scheduler_pid, {:job_finished, job.id})
            end
          end)

        MapSet.put(acc, job.id)
      end)

    schedule_poll()
    {:noreply, %{state | running_jobs: running_ids}}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, Config.scheduler_poll_ms())
  end

  defp schedule_retention do
    Process.send_after(self(), :retention_cleanup, @retention_interval_ms)
  end
end
