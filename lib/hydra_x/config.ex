defmodule HydraX.Config do
  @moduledoc """
  Runtime configuration helpers for workspace paths and process tuning.
  """

  @default_workspace_root "workspace"

  @spec repo_adapter() :: module()
  def repo_adapter do
    Application.get_env(:hydra_x, :repo_adapter, HydraX.Repo.__adapter__())
  end

  @spec repo_backend() :: String.t()
  def repo_backend do
    Application.get_env(:hydra_x, :repo_backend) ||
      case repo_adapter() do
        Ecto.Adapters.Postgres -> "postgres"
        Ecto.Adapters.SQLite3 -> "sqlite"
        adapter -> adapter |> Module.split() |> List.last() |> Macro.underscore()
      end
  end

  @spec repo_sqlite?() :: boolean()
  def repo_sqlite?, do: repo_adapter() == Ecto.Adapters.SQLite3

  @spec repo_postgres?() :: boolean()
  def repo_postgres?, do: repo_adapter() == Ecto.Adapters.Postgres

  @spec repo_multi_writer?() :: boolean()
  def repo_multi_writer?, do: repo_postgres?()

  @spec workspace_root() :: String.t()
  def workspace_root do
    System.get_env("HYDRA_X_WORKSPACE_ROOT") ||
      Path.expand(@default_workspace_root, File.cwd!())
  end

  @spec repo_database_path() :: String.t() | nil
  def repo_database_path do
    repo_config()
    |> Keyword.get(:database)
    |> case do
      nil -> nil
      path -> Path.expand(path)
    end
  end

  @spec repo_database_url() :: String.t() | nil
  def repo_database_url do
    repo_config()
    |> Keyword.get(:url)
  end

  @spec repo_target() :: String.t() | nil
  def repo_target do
    case repo_backend() do
      "postgres" -> repo_database_url() || postgres_target_from_config()
      _ -> repo_database_path()
    end
  end

  @spec repo_target_kind() :: String.t()
  def repo_target_kind do
    if repo_postgres?(), do: "database_url", else: "database_path"
  end

  @spec repo_persistence_status() :: map()
  def repo_persistence_status do
    %{
      backend: repo_backend(),
      adapter: repo_adapter() |> Module.split() |> List.last(),
      target: repo_target(),
      target_kind: repo_target_kind(),
      multi_writer: repo_multi_writer?(),
      backup_mode: if(repo_postgres?(), do: "external_database", else: "bundled_database")
    }
  end

  @spec backup_root() :: String.t()
  def backup_root do
    System.get_env("HYDRA_X_BACKUP_ROOT") ||
      Path.expand("backups", File.cwd!())
  end

  @spec install_root() :: String.t()
  def install_root do
    System.get_env("HYDRA_X_INSTALL_ROOT") ||
      Path.expand("install", File.cwd!())
  end

  @spec default_workspace(String.t()) :: String.t()
  def default_workspace(agent_slug) do
    Path.join(workspace_root(), agent_slug)
  end

  @spec coalesce_window_ms() :: non_neg_integer()
  def coalesce_window_ms do
    env_integer("HYDRA_X_COALESCE_WINDOW_MS", 250)
  end

  @spec cortex_interval_ms() :: non_neg_integer()
  def cortex_interval_ms do
    env_integer("HYDRA_X_CORTEX_INTERVAL_MS", 60_000)
  end

  @spec scheduler_poll_ms() :: non_neg_integer()
  def scheduler_poll_ms do
    env_integer("HYDRA_X_SCHEDULER_POLL_MS", 15_000)
  end

  @spec compaction_thresholds() :: %{
          soft: pos_integer(),
          medium: pos_integer(),
          hard: pos_integer()
        }
  def compaction_thresholds do
    %{
      soft: env_integer("HYDRA_X_COMPACTOR_SOFT_TURNS", 12),
      medium: env_integer("HYDRA_X_COMPACTOR_MEDIUM_TURNS", 18),
      hard: env_integer("HYDRA_X_COMPACTOR_HARD_TURNS", 24)
    }
  end

  @spec public_base_url() :: String.t()
  def public_base_url do
    System.get_env("HYDRA_X_PUBLIC_URL") ||
      endpoint_base_url()
  end

  @spec secret_key() :: String.t()
  def secret_key do
    System.get_env("HYDRA_X_SECRET_KEY") ||
      endpoint_secret_key_base() ||
      "hydra-x-dev-secret"
  end

  @spec endpoint_secret_key_base() :: String.t() | nil
  def endpoint_secret_key_base do
    Application.get_env(:hydra_x, HydraXWeb.Endpoint, [])
    |> Keyword.get(:secret_key_base)
  end

  @spec telegram_webhook_url() :: String.t()
  def telegram_webhook_url do
    String.trim_trailing(public_base_url(), "/") <> "/api/telegram/webhook"
  end

  @spec shell_allowlist() :: [String.t()]
  def shell_allowlist do
    System.get_env("HYDRA_X_SHELL_ALLOWLIST", "pwd,ls,cat,head,rg,git")
    |> String.split(",", trim: true)
  end

  @spec http_allowlist() :: [String.t()]
  def http_allowlist do
    System.get_env("HYDRA_X_HTTP_ALLOWLIST", "")
    |> String.split(",", trim: true)
  end

  @spec embedding_backend() :: String.t()
  def embedding_backend do
    System.get_env("HYDRA_X_EMBEDDING_BACKEND", "local_hash_v1")
  end

  @spec embedding_model() :: String.t()
  def embedding_model do
    System.get_env("HYDRA_X_EMBEDDING_MODEL", "text-embedding-3-small")
  end

  @spec embedding_url() :: String.t() | nil
  def embedding_url do
    System.get_env("HYDRA_X_EMBEDDING_URL")
  end

  @spec embedding_api_key() :: String.t() | nil
  def embedding_api_key do
    System.get_env("HYDRA_X_EMBEDDING_API_KEY")
  end

  defp endpoint_base_url do
    endpoint = Application.get_env(:hydra_x, HydraXWeb.Endpoint, [])
    url = Keyword.get(endpoint, :url, [])
    host = Keyword.get(url, :host, "localhost")
    scheme = Keyword.get(url, :scheme, "http")
    port = Keyword.get(url, :port, 4000)

    case {scheme, port} do
      {"http", 80} -> "#{scheme}://#{host}"
      {"https", 443} -> "#{scheme}://#{host}"
      _ -> "#{scheme}://#{host}:#{port}"
    end
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp repo_config do
    Application.get_env(:hydra_x, HydraX.Repo, [])
  end

  defp postgres_target_from_config do
    config = repo_config()
    hostname = Keyword.get(config, :hostname)
    database = Keyword.get(config, :database)

    case {hostname, database} do
      {host, db} when is_binary(host) and is_binary(db) -> "ecto://#{host}/#{db}"
      {host, _db} when is_binary(host) -> "ecto://#{host}"
      _ -> nil
    end
  end
end
