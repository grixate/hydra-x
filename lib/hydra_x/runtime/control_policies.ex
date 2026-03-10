defmodule HydraX.Runtime.ControlPolicies do
  @moduledoc """
  Cross-cutting runtime policy covering auth freshness, delivery constraints,
  and ingest roots.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.{ControlPolicy, Helpers}

  @default_channels ~w(telegram discord slack webchat)
  @default_ingest_roots ["ingest"]

  def get_control_policy do
    Repo.one(
      from(policy in ControlPolicy,
        where: policy.scope == "default" and is_nil(policy.agent_id),
        limit: 1
      )
    )
  end

  def ensure_control_policy! do
    case get_control_policy() do
      nil ->
        {:ok, policy} =
          save_control_policy(%{
            scope: "default",
            require_recent_auth_for_sensitive_actions: true,
            recent_auth_window_minutes: 15,
            interactive_delivery_channels_csv: Enum.join(@default_channels, ","),
            job_delivery_channels_csv: Enum.join(@default_channels, ","),
            ingest_roots_csv: Enum.join(@default_ingest_roots, ",")
          })

        policy

      policy ->
        policy
    end
  end

  def change_control_policy(policy \\ nil, attrs \\ %{}) do
    (policy || get_control_policy() || %ControlPolicy{scope: "default"})
    |> ControlPolicy.changeset(attrs)
  end

  def save_control_policy(attrs) when is_map(attrs) do
    save_control_policy(get_control_policy() || %ControlPolicy{}, attrs)
  end

  def save_control_policy(%ControlPolicy{} = policy, attrs) do
    policy
    |> ControlPolicy.changeset(
      Helpers.normalize_string_keys(attrs)
      |> Map.put_new("scope", "default")
    )
    |> Repo.insert_or_update()
  end

  def get_agent_control_policy(nil), do: nil

  def get_agent_control_policy(agent_id) do
    Repo.one(
      from(policy in ControlPolicy,
        where: policy.scope == "default" and policy.agent_id == ^agent_id,
        limit: 1
      )
    )
  end

  def save_agent_control_policy(agent_id, attrs) when is_integer(agent_id) do
    existing = get_agent_control_policy(agent_id) || %ControlPolicy{agent_id: agent_id}

    existing
    |> ControlPolicy.changeset(
      Helpers.normalize_string_keys(attrs)
      |> Map.put("scope", "default")
      |> Map.put("agent_id", agent_id)
    )
    |> Repo.insert_or_update()
  end

  def delete_agent_control_policy!(agent_id) when is_integer(agent_id) do
    case get_agent_control_policy(agent_id) do
      nil -> :ok
      policy -> Repo.delete!(policy)
    end
  end

  def effective_control_policy(agent_id \\ nil) do
    policy =
      case agent_id do
        nil -> get_control_policy()
        id -> get_agent_control_policy(id) || get_control_policy()
      end || %ControlPolicy{}

    %{
      require_recent_auth_for_sensitive_actions:
        Map.get(policy, :require_recent_auth_for_sensitive_actions, true),
      recent_auth_window_minutes: Map.get(policy, :recent_auth_window_minutes, 15),
      interactive_delivery_channels:
        csv_values(policy.interactive_delivery_channels_csv, @default_channels),
      job_delivery_channels: csv_values(policy.job_delivery_channels_csv, @default_channels),
      ingest_roots: csv_values(policy.ingest_roots_csv, @default_ingest_roots)
    }
  end

  defp csv_values(nil, fallback), do: fallback
  defp csv_values("", fallback), do: fallback

  defp csv_values(csv, _fallback) when is_binary(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
