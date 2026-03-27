defmodule HydraX.Simulation.Supervisor do
  @moduledoc """
  Top-level supervisor for a single simulation instance.

  Supervises the World GenServer, Clock, and a DynamicSupervisor for SimAgents.
  Each simulation gets its own supervisor tree, started under HydraX.AgentSupervisor.
  """

  use Supervisor

  def start_link(opts) do
    sim_id = Keyword.fetch!(opts, :sim_id)
    name = {:via, Registry, {HydraX.Simulation.Registry, {:supervisor, sim_id}}}
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    sim_id = Keyword.fetch!(opts, :sim_id)

    children = [
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: {:via, Registry, {HydraX.Simulation.Registry, {:agent_sup, sim_id}}}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
