defmodule HydraX.Runtime.Providers do
  @moduledoc """
  Provider configuration CRUD, tool policy management, and provider testing.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Repo

  alias HydraX.Runtime.{Helpers, ProviderConfig, ToolPolicy}

  def list_provider_configs do
    ProviderConfig
    |> order_by([provider], desc: provider.enabled, asc: provider.name)
    |> Repo.all()
  end

  def get_provider_config!(id), do: Repo.get!(ProviderConfig, id)

  def enabled_provider do
    Repo.one(from(provider in ProviderConfig, where: provider.enabled == true, limit: 1))
  end

  def change_provider_config(provider \\ %ProviderConfig{}, attrs \\ %{}) do
    ProviderConfig.changeset(provider, attrs)
  end

  def save_provider_config(attrs) when is_map(attrs) do
    save_provider_config(%ProviderConfig{}, attrs)
  end

  def save_provider_config(%ProviderConfig{} = provider, attrs) do
    Repo.transaction(fn ->
      changeset = ProviderConfig.changeset(provider, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in ProviderConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      record
    end)
    |> Helpers.unwrap_transaction()
  end

  def activate_provider!(id) do
    provider = get_provider_config!(id)
    {:ok, updated} = save_provider_config(provider, %{enabled: true})
    updated
  end

  def toggle_provider_enabled!(id) do
    provider = get_provider_config!(id)
    {:ok, updated} = save_provider_config(provider, %{enabled: !provider.enabled})
    updated
  end

  def delete_provider_config!(id) do
    provider = get_provider_config!(id)
    Repo.delete!(provider)
  end

  # -- Global tool policy --

  def get_tool_policy do
    Repo.one(
      from(tp in ToolPolicy, where: tp.scope == "default" and is_nil(tp.agent_id), limit: 1)
    )
  end

  def ensure_tool_policy! do
    case get_tool_policy() do
      nil ->
        {:ok, policy} =
          save_tool_policy(%{
            scope: "default",
            workspace_read_enabled: true,
            http_fetch_enabled: true,
            shell_command_enabled: true
          })

        policy

      policy ->
        policy
    end
  end

  def change_tool_policy(policy \\ nil, attrs \\ %{}) do
    (policy || get_tool_policy() || %ToolPolicy{scope: "default"})
    |> ToolPolicy.changeset(attrs)
  end

  def save_tool_policy(attrs) when is_map(attrs) do
    save_tool_policy(get_tool_policy() || %ToolPolicy{}, attrs)
  end

  def save_tool_policy(%ToolPolicy{} = policy, attrs) do
    policy
    |> ToolPolicy.changeset(
      Helpers.normalize_string_keys(attrs) |> Map.put_new("scope", "default")
    )
    |> Repo.insert_or_update()
  end

  # -- Per-agent tool policy --

  @doc "Returns the agent-specific tool policy, or nil if none exists."
  def get_agent_tool_policy(nil), do: nil

  def get_agent_tool_policy(agent_id) do
    Repo.one(
      from(tp in ToolPolicy,
        where: tp.scope == "default" and tp.agent_id == ^agent_id,
        limit: 1
      )
    )
  end

  @doc "Create or update a per-agent tool policy."
  def save_agent_tool_policy(agent_id, attrs) when is_integer(agent_id) do
    existing = get_agent_tool_policy(agent_id) || %ToolPolicy{agent_id: agent_id}

    existing
    |> ToolPolicy.changeset(
      Helpers.normalize_string_keys(attrs)
      |> Map.put("scope", "default")
      |> Map.put("agent_id", agent_id)
    )
    |> Repo.insert_or_update()
  end

  @doc "Remove an agent-specific tool policy (agent falls back to global)."
  def delete_agent_tool_policy!(agent_id) when is_integer(agent_id) do
    case get_agent_tool_policy(agent_id) do
      nil -> :ok
      policy -> Repo.delete!(policy)
    end
  end

  # -- Policy resolution --

  @doc """
  Returns the effective tool policy for the given agent.

  Resolution order: agent-specific policy → global default → built-in defaults.
  Pass `nil` or omit the argument for the global policy.
  """
  def effective_tool_policy(agent_id \\ nil) do
    policy =
      case agent_id do
        nil -> get_tool_policy()
        id -> get_agent_tool_policy(id) || get_tool_policy()
      end || %ToolPolicy{}

    %{
      workspace_read_enabled: Map.get(policy, :workspace_read_enabled, true),
      http_fetch_enabled: Map.get(policy, :http_fetch_enabled, true),
      shell_command_enabled: Map.get(policy, :shell_command_enabled, true),
      shell_allowlist: csv_values(policy.shell_allowlist_csv, Config.shell_allowlist()),
      http_allowlist: csv_values(policy.http_allowlist_csv, Config.http_allowlist())
    }
  end

  def test_provider_config(%ProviderConfig{} = provider, opts \\ []) do
    request =
      %{
        provider_config: provider,
        messages: [
          %{role: "system", content: "You are a terse provider connectivity probe."},
          %{role: "user", content: "Reply with OK if you can read this request."}
        ],
        bulletin: nil,
        request_options:
          Keyword.get(opts, :request_options, receive_timeout: 10_000, retry: false)
      }
      |> maybe_put_request_fn_from_config()
      |> maybe_put_request_fn(opts)

    provider
    |> provider_module()
    |> apply(:complete, [request])
  end

  # -- Private helpers --

  defp provider_module(%ProviderConfig{kind: "openai_compatible"}),
    do: HydraX.LLM.Providers.OpenAICompatible

  defp provider_module(%ProviderConfig{kind: "anthropic"}), do: HydraX.LLM.Providers.Anthropic

  defp maybe_put_request_fn(request, opts) do
    case Keyword.get(opts, :request_fn) do
      nil -> request
      request_fn -> Map.put(request, :request_fn, request_fn)
    end
  end

  defp maybe_put_request_fn_from_config(request) do
    case Application.get_env(:hydra_x, :provider_test_request_fn) do
      nil -> request
      request_fn -> Map.put(request, :request_fn, request_fn)
    end
  end

  defp csv_values(nil, fallback), do: fallback
  defp csv_values("", fallback), do: fallback

  defp csv_values(csv, _fallback) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end
end
