defmodule HydraX.Scheduler do
  @moduledoc false
  use GenServer

  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.Gateway
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

    {:ok,
     %{
       running_jobs: MapSet.new(),
       coordination: scheduler_coordination_snapshot(),
       pending_ingress: pending_ingress_snapshot(),
       role_queue_dispatches: role_queue_dispatch_snapshot(),
       work_item_replays: work_item_replay_snapshot(),
       ownership_handoffs: ownership_handoff_snapshot(),
       deferred_deliveries: deferred_delivery_snapshot()
     }}
  end

  @impl true
  def handle_info(:poll, state) do
    case scheduler_owner_check() do
      {:run, coordination} ->
        do_poll(%{state | coordination: coordination})

      {:skip, coordination} ->
        schedule_poll()
        {:noreply, %{state | coordination: coordination}}
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
    pending_ingress = Gateway.process_owned_ingress(limit: 50)
    role_queue_dispatches = Runtime.process_role_queued_work(limit: 50)
    work_item_replays = Runtime.resume_owned_work_items(limit: 50)
    ownership_handoffs = Runtime.resume_owned_conversations(limit: 50)
    deferred_deliveries = Gateway.process_deferred_deliveries(limit: 50)

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

    {:noreply,
     %{
       state
       | running_jobs: running_ids,
         pending_ingress: pending_ingress,
         role_queue_dispatches: role_queue_dispatches,
         work_item_replays: work_item_replays,
         ownership_handoffs: ownership_handoffs,
         deferred_deliveries: deferred_deliveries
     }}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, Config.scheduler_poll_ms())
  end

  defp schedule_retention do
    Process.send_after(self(), :retention_cleanup, @retention_interval_ms)
  end

  defp scheduler_owner_check do
    if Config.repo_multi_writer?() do
      case Runtime.claim_lease("scheduler:poller",
             ttl_seconds: scheduler_ttl_seconds(),
             metadata: %{
               "role" => "scheduler",
               "poll_ms" => Config.scheduler_poll_ms()
             }
           ) do
        {:ok, lease} ->
          {:run, coordination_snapshot("database_lease", lease.owner, lease.expires_at)}

        {:error, {:taken, lease}} ->
          {:skip, coordination_snapshot("database_lease", lease.owner, lease.expires_at)}

        {:error, _reason} ->
          {:skip, coordination_snapshot("database_lease", "unavailable", nil)}
      end
    else
      if Cluster.leader?() do
        {:run, coordination_snapshot("local_leader", to_string(Cluster.node_id()), nil)}
      else
        {:skip, coordination_snapshot("local_leader", "other_node", nil)}
      end
    end
  end

  defp scheduler_ttl_seconds do
    max(div(Config.scheduler_poll_ms() * 3, 1000), 15)
  end

  defp scheduler_coordination_snapshot do
    coordination_snapshot(
      if(Config.repo_multi_writer?(), do: "database_lease", else: "local_leader"),
      to_string(Cluster.node_id()),
      nil
    )
  end

  defp coordination_snapshot(mode, owner, expires_at) do
    %{
      mode: mode,
      owner: owner,
      expires_at: expires_at
    }
  end

  defp ownership_handoff_snapshot do
    %{
      owner: Runtime.coordination_status().owner,
      resumed_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp work_item_replay_snapshot do
    %{
      owner: Runtime.coordination_status().owner,
      resumed_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp role_queue_dispatch_snapshot do
    %{
      owner: Runtime.coordination_status().owner,
      processed_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp pending_ingress_snapshot do
    %{
      owner: Runtime.coordination_status().owner,
      processed_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end

  defp deferred_delivery_snapshot do
    %{
      owner: Runtime.coordination_status().owner,
      delivered_count: 0,
      skipped_count: 0,
      error_count: 0,
      results: []
    }
  end
end
