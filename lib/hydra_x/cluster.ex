defmodule HydraX.Cluster do
  @moduledoc """
  Cluster awareness module for multi-node preparation.

  Provides leader election via `:global` registration and node
  identification. Disabled by default — enable via HYDRA_CLUSTER_ENABLED=true.

  ## Current Limitations

  - SQLite is a single-writer database. True multi-node with SQLite is impractical.
  - This module adds the OTP plumbing for distributed awareness.
  - A PostgreSQL migration path is required for production multi-node deployments.

  ## Usage

      # Check if clustering is enabled
      HydraX.Cluster.enabled?()

      # Get unique node identifier
      HydraX.Cluster.node_id()

      # Check if this node is the cluster leader
      HydraX.Cluster.leader?()

  ## Configuration

      # Environment variable
      HYDRA_CLUSTER_ENABLED=true

      # Application config
      config :hydra_x, :cluster_enabled, true
  """

  @leader_key :hydra_x_cluster_leader

  @doc "Returns true if clustering is enabled."
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:hydra_x, :cluster_enabled, false)
  end

  @doc "Returns a unique identifier for the current node."
  @spec node_id() :: atom()
  def node_id do
    Node.self()
  end

  @doc """
  Returns true if this node is the cluster leader.

  Uses `:global.register_name/3` for leader election. The first node
  to register wins. When not in cluster mode, always returns true.
  """
  @spec leader?() :: boolean()
  def leader? do
    if enabled?() do
      case :global.register_name(@leader_key, self(), &resolve_conflict/3) do
        :yes ->
          true

        :no ->
          # Check if we are the registered process
          case :global.whereis_name(@leader_key) do
            :undefined -> true
            pid -> pid == self()
          end
      end
    else
      # Single-node mode — always leader
      true
    end
  end

  @doc "Returns the PID of the current leader, or :undefined."
  @spec leader_pid() :: pid() | :undefined
  def leader_pid do
    if enabled?() do
      :global.whereis_name(@leader_key)
    else
      self()
    end
  end

  @doc "Returns all connected nodes (including self)."
  @spec nodes() :: [atom()]
  def nodes do
    if enabled?() do
      [Node.self() | Node.list()]
    else
      [Node.self()]
    end
  end

  # Conflict resolution — keep the existing registered process
  defp resolve_conflict(_name, pid1, _pid2), do: pid1
end
