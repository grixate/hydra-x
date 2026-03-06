defmodule HydraX.Scheduler do
  @moduledoc false
  use GenServer

  alias HydraX.Config
  alias HydraX.Runtime

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    Runtime.list_due_scheduled_jobs(DateTime.utc_now())
    |> Enum.each(fn job ->
      Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
        Runtime.run_scheduled_job(job)
      end)
    end)

    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, Config.scheduler_poll_ms())
  end
end
