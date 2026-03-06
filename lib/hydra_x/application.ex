defmodule HydraX.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HydraXWeb.Telemetry,
      HydraX.Telemetry.Store,
      HydraX.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:hydra_x, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:hydra_x, :dns_cluster_query) || :ignore},
      {Registry, keys: :unique, name: HydraX.ProcessRegistry},
      {Phoenix.PubSub, name: HydraX.PubSub},
      {Task.Supervisor, name: HydraX.TaskSupervisor},
      HydraX.AgentSupervisor,
      HydraX.Scheduler,
      HydraX.Runtime.Bootstrap,
      HydraXWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HydraX.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HydraXWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
