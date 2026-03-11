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

  @doc "Returns a node-aware cluster status snapshot without mutating leadership."
  @spec status() :: map()
  def status do
    enabled = enabled?()
    nodes = nodes()
    leader_pid = if(enabled, do: :global.whereis_name(@leader_key), else: self())
    persistence = HydraX.Config.repo_persistence_status()

    %{
      enabled: enabled,
      mode: if(enabled, do: "cluster", else: "single_node"),
      node_id: node_id() |> to_string(),
      distributed: Node.alive?(),
      node_count: length(nodes),
      nodes: Enum.map(nodes, &to_string/1),
      leader_registered: leader_pid != :undefined,
      leader_node: leader_node(leader_pid),
      persistence: persistence_label(persistence),
      persistence_backend: persistence.backend,
      persistence_target: persistence.target,
      multi_node_ready: false
    }
    |> Map.put(:detail, detail(enabled, leader_pid, nodes))
  end

  # Conflict resolution — keep the existing registered process
  defp resolve_conflict(_name, pid1, _pid2), do: pid1

  defp leader_node(:undefined), do: nil
  defp leader_node(pid) when is_pid(pid), do: pid |> node() |> to_string()

  defp detail(false, _leader_pid, nodes) do
    if HydraX.Config.repo_multi_writer?() do
      "single-node mode on #{node_id()}; #{length(nodes)} visible node; PostgreSQL persistence is configured for post-preview architecture work"
    else
      "single-node mode on #{node_id()}; #{length(nodes)} visible node; SQLite is acceptable until federation begins"
    end
  end

  defp detail(true, :undefined, nodes) do
    if HydraX.Config.repo_multi_writer?() do
      "cluster awareness enabled on #{node_id()} with #{length(nodes)} visible nodes; no leader registered yet; PostgreSQL persistence is configured but distributed ownership and routing are still pending"
    else
      "cluster awareness enabled on #{node_id()} with #{length(nodes)} visible nodes; no leader registered yet; SQLite still blocks production multi-node operation"
    end
  end

  defp detail(true, leader_pid, nodes) when is_pid(leader_pid) do
    if HydraX.Config.repo_multi_writer?() do
      "cluster awareness enabled on #{node_id()} with #{length(nodes)} visible nodes; leader #{leader_node(leader_pid)}; PostgreSQL persistence is configured but distributed ownership and routing are still pending"
    else
      "cluster awareness enabled on #{node_id()} with #{length(nodes)} visible nodes; leader #{leader_node(leader_pid)}; SQLite still blocks production multi-node operation"
    end
  end

  defp persistence_label(%{backend: "postgres"}), do: "postgres_multi_writer_ready"
  defp persistence_label(_), do: "sqlite_single_writer"
end
