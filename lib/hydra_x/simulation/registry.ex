defmodule HydraX.Simulation.Registry do
  @moduledoc """
  Process registry for simulation agents.

  Wraps Elixir's Registry for SimAgent process lookup by {sim_id, agent_id} tuples.
  Started as part of the application supervision tree.
  """

  @doc """
  Child spec for the simulation registry.
  """
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @doc """
  Look up a SimAgent process by sim_id and agent_id.
  """
  @spec lookup(String.t(), String.t()) :: {:ok, pid()} | :error
  def lookup(sim_id, agent_id) do
    case Registry.lookup(__MODULE__, {sim_id, agent_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  List all agent IDs for a given simulation.
  """
  @spec list_agents(String.t()) :: [String.t()]
  def list_agents(sim_id) do
    Registry.select(__MODULE__, [
      {{{sim_id, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
  end

  @doc """
  Count agents for a given simulation.
  """
  @spec count_agents(String.t()) :: non_neg_integer()
  def count_agents(sim_id) do
    list_agents(sim_id) |> length()
  end

  @doc """
  Look up a named infrastructure process (world, clock, agent_sup) for a simulation.
  """
  @spec lookup_process(String.t(), atom()) :: {:ok, pid()} | :error
  def lookup_process(sim_id, process_key) do
    case Registry.lookup(__MODULE__, {process_key, sim_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
