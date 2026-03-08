defmodule HydraX.Agent do
  @moduledoc """
  Top-level supervisor for a single agent identity.
  """

  use Supervisor

  alias HydraX.ProcessRegistry
  alias HydraX.Runtime.AgentProfile

  def start_link(%AgentProfile{} = agent) do
    Supervisor.start_link(__MODULE__, agent, name: via_name(agent.id))
  end

  def ensure_started(%AgentProfile{} = agent) do
    case Registry.lookup(HydraX.ProcessRegistry, {:agent, agent.id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> DynamicSupervisor.start_child(HydraX.AgentSupervisor, {__MODULE__, agent})
    end
  end

  def ensure_stopped(%AgentProfile{} = agent) do
    case pid(agent.id) do
      nil ->
        :ok

      running_pid ->
        case DynamicSupervisor.terminate_child(HydraX.AgentSupervisor, running_pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
        end
    end
  end

  def restart(%AgentProfile{} = agent) do
    with :ok <- ensure_stopped(agent) do
      ensure_started(agent)
    end
  end

  def stop_all do
    if Process.whereis(HydraX.AgentSupervisor) do
      HydraX.AgentSupervisor
      |> DynamicSupervisor.which_children()
      |> Enum.each(fn
        {_, pid, _, _} when is_pid(pid) ->
          case DynamicSupervisor.terminate_child(HydraX.AgentSupervisor, pid) do
            :ok -> :ok
            {:error, :not_found} -> :ok
          end

        _ ->
          :ok
      end)
    end

    :ok
  end

  def pid(agent_id) do
    case Registry.lookup(HydraX.ProcessRegistry, {:agent, agent_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def running?(%AgentProfile{} = agent), do: running?(agent.id)
  def running?(agent_id), do: not is_nil(pid(agent_id))

  def via_name(agent_id), do: ProcessRegistry.via({:agent, agent_id})
  def channel_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :channels})
  def branch_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :branches})
  def worker_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :workers})
  def compactor_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :compactors})

  @impl true
  def init(agent) do
    ingest_path = Path.join(agent.workspace_root || "", "ingest")

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: channel_supervisor(agent.id)},
      {DynamicSupervisor, strategy: :one_for_one, name: branch_supervisor(agent.id)},
      {DynamicSupervisor, strategy: :one_for_one, name: worker_supervisor(agent.id)},
      {DynamicSupervisor, strategy: :one_for_one, name: compactor_supervisor(agent.id)},
      {HydraX.Agent.Cortex, agent_id: agent.id},
      {HydraX.Ingest.Watcher, agent_id: agent.id, ingest_path: ingest_path}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
