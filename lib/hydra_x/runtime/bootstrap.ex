defmodule HydraX.Runtime.Bootstrap do
  @moduledoc false
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    if Application.get_env(:hydra_x, :bootstrap_runtime, true) do
      send(self(), :bootstrap)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:bootstrap, state) do
    agent = HydraX.Runtime.ensure_default_agent!()
    HydraX.Budget.ensure_policy!(agent.id)
    HydraX.Agent.ensure_started(agent)
    HydraX.Runtime.ensure_heartbeat_job!(agent.id)
    HydraX.Runtime.ensure_backup_job!(agent.id)
    {:noreply, Map.put(state, :bootstrapped_at, DateTime.utc_now())}
  end
end
