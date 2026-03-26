defmodule HydraX.Operator.Production do
  @moduledoc false

  alias HydraX.Cluster
  alias HydraX.Config

  def operating_mode do
    cond do
      Config.repo_postgres?() and Cluster.enabled?() -> :production_multi_node
      Config.repo_postgres?() -> :local_single_node
      true -> :local_single_node
    end
  end

  def production_readiness do
    [
      %{
        step: "PostgreSQL configured",
        done: Config.repo_postgres?(),
        required: true
      },
      %{
        step: "SECRET_KEY_BASE set",
        done: has_secret_key_base?(),
        required: true
      },
      %{
        step: "HYDRA_X_SECRET_KEY set",
        done: has_secret_key?(),
        required: true
      },
      %{
        step: "PHX_HOST configured",
        done: has_custom_host?(),
        required: true
      },
      %{
        step: "Operator password set",
        done: has_operator_password?(),
        required: true
      },
      %{
        step: "Clustering enabled",
        done: Cluster.enabled?(),
        required: false
      },
      %{
        step: "Backup strategy configured",
        done: has_backup_config?(),
        required: false
      }
    ]
  end

  def migration_checklist, do: production_readiness()

  def production_blockers do
    production_readiness()
    |> Enum.filter(&(&1.required and not &1.done))
    |> Enum.map(& &1.step)
  end

  defp has_secret_key_base? do
    case System.get_env("SECRET_KEY_BASE") do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp has_secret_key? do
    case System.get_env("HYDRA_X_SECRET_KEY") do
      nil -> false
      "hydra-x-dev-secret" -> false
      "" -> false
      _ -> true
    end
  end

  defp has_custom_host? do
    case System.get_env("PHX_HOST") do
      nil -> false
      "localhost" -> false
      "" -> false
      _ -> true
    end
  end

  defp has_operator_password? do
    case HydraX.Runtime.OperatorSecret |> HydraX.Repo.one() do
      nil -> false
      _ -> true
    end
  rescue
    _ -> false
  end

  defp has_backup_config? do
    case HydraX.Runtime.Jobs.list_scheduled_jobs(kind: "backup", enabled: true) do
      [] -> false
      _ -> true
    end
  rescue
    _ -> false
  end
end
