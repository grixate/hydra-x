defmodule HydraX.Runtime.Coordination do
  @moduledoc """
  Shared coordination leases for post-preview ownership groundwork.
  """

  import Ecto.Query

  alias HydraX.Cluster
  alias HydraX.Config
  alias HydraX.Repo
  alias HydraX.Runtime.CoordinationLease

  @default_ttl_seconds 30

  def claim_lease(name, opts \\ []) when is_binary(name) do
    owner = Keyword.get(opts, :owner, default_owner())
    metadata = Map.new(Keyword.get(opts, :metadata, %{}))
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl_seconds, :second)

    Repo.transaction(fn ->
      case locked_lease(name) do
        nil ->
          insert_lease!(name, owner, expires_at, metadata)

        %CoordinationLease{} = lease ->
          cond do
            lease.owner == owner ->
              update_lease!(lease, owner, expires_at, metadata)

            lease_expired?(lease, now) ->
              update_lease!(lease, owner, expires_at, metadata)

            true ->
              Repo.rollback({:taken, lease})
          end
      end
    end)
    |> unwrap_transaction()
  end

  def release_lease(name, opts \\ []) when is_binary(name) do
    owner = Keyword.get(opts, :owner, default_owner())

    Repo.transaction(fn ->
      case locked_lease(name) do
        nil ->
          :ok

        %CoordinationLease{} = lease when lease.owner == owner ->
          Repo.delete!(lease)
          :ok

        %CoordinationLease{} = lease ->
          Repo.rollback({:not_owner, lease})
      end
    end)
    |> unwrap_release()
  end

  def get_lease(name) when is_binary(name) do
    query =
      from lease in CoordinationLease,
        where: lease.name == ^name

    Repo.one(query)
  end

  def active_lease(name) when is_binary(name) do
    case get_lease(name) do
      %CoordinationLease{} = lease ->
        if lease_expired?(lease, DateTime.utc_now()), do: nil, else: lease

      nil ->
        nil
    end
  end

  def list_active_leases do
    now = DateTime.utc_now()

    CoordinationLease
    |> where([lease], lease.expires_at > ^now)
    |> order_by([lease], asc: lease.name)
    |> Repo.all()
  end

  def status do
    active_leases = list_active_leases()
    scheduler_lease = Enum.find(active_leases, &(&1.name == "scheduler:poller"))

    %{
      mode: coordination_mode(),
      backend: Config.repo_backend(),
      enabled: Config.repo_multi_writer?(),
      owner: default_owner(),
      lease_count: length(active_leases),
      active_leases: Enum.map(active_leases, &lease_summary/1),
      scheduler_owner: scheduler_lease && scheduler_lease.owner,
      scheduler_expires_at: scheduler_lease && scheduler_lease.expires_at
    }
  end

  def coordination_mode do
    if Config.repo_multi_writer?(), do: "database_leases", else: "local_single_node"
  end

  defp locked_lease(name) do
    query =
      from lease in CoordinationLease,
        where: lease.name == ^name

    if Config.repo_postgres?() and postgres_adapter_loaded?() do
      Repo.one(from lease in query, lock: "FOR UPDATE")
    else
      Repo.one(query)
    end
  end

  defp insert_lease!(name, owner, expires_at, metadata) do
    %CoordinationLease{}
    |> CoordinationLease.changeset(%{
      name: name,
      owner: owner,
      owner_node: owner_node(),
      expires_at: expires_at,
      metadata: metadata
    })
    |> Repo.insert!()
  end

  defp update_lease!(lease, owner, expires_at, metadata) do
    lease
    |> CoordinationLease.changeset(%{
      owner: owner,
      owner_node: owner_node(),
      expires_at: expires_at,
      metadata: Map.merge(lease.metadata || %{}, metadata)
    })
    |> Repo.update!()
  end

  defp lease_expired?(lease, now), do: DateTime.compare(lease.expires_at, now) != :gt

  defp unwrap_transaction({:ok, %CoordinationLease{} = lease}), do: {:ok, lease}

  defp unwrap_transaction({:error, {:taken, %CoordinationLease{} = lease}}),
    do: {:error, {:taken, lease}}

  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp unwrap_release({:ok, :ok}), do: :ok

  defp unwrap_release({:error, {:not_owner, %CoordinationLease{} = lease}}),
    do: {:error, {:not_owner, lease}}

  defp unwrap_release({:error, reason}), do: {:error, reason}

  defp lease_summary(lease) do
    %{
      name: lease.name,
      owner: lease.owner,
      owner_node: lease.owner_node,
      expires_at: lease.expires_at,
      metadata: lease.metadata || %{}
    }
  end

  defp default_owner do
    "node:" <> owner_node()
  end

  defp postgres_adapter_loaded? do
    Repo.__adapter__()
    |> to_string()
    |> Kernel.==("Elixir.Ecto.Adapters.Postgres")
  end

  defp owner_node do
    Cluster.node_id()
    |> to_string()
  end
end
