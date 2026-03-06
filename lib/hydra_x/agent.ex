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

  def via_name(agent_id), do: ProcessRegistry.via({:agent, agent_id})
  def channel_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :channels})
  def branch_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :branches})
  def worker_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :workers})
  def compactor_supervisor(agent_id), do: ProcessRegistry.via({:agent, agent_id, :compactors})

  @impl true
  def init(agent) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: channel_supervisor(agent.id)},
      {DynamicSupervisor, strategy: :one_for_one, name: branch_supervisor(agent.id)},
      {DynamicSupervisor, strategy: :one_for_one, name: worker_supervisor(agent.id)},
      {DynamicSupervisor, strategy: :one_for_one, name: compactor_supervisor(agent.id)},
      {HydraX.Agent.Cortex, agent_id: agent.id}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
