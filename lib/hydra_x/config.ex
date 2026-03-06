defmodule HydraX.Config do
  @moduledoc """
  Runtime configuration helpers for workspace paths and process tuning.
  """

  @default_workspace_root "workspace"

  @spec workspace_root() :: String.t()
  def workspace_root do
    System.get_env("HYDRA_X_WORKSPACE_ROOT") ||
      Path.expand(@default_workspace_root, File.cwd!())
  end

  @spec repo_database_path() :: String.t()
  def repo_database_path do
    Application.get_env(:hydra_x, HydraX.Repo, [])
    |> Keyword.fetch!(:database)
    |> Path.expand()
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
end
