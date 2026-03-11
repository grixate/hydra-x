defmodule HydraX.Runtime.Providers do
  @moduledoc """
  Provider configuration CRUD, tool policy management, and provider testing.
  """

  import Ecto.Query

  alias HydraX.Budget
  alias HydraX.Config
  alias HydraX.Repo
  alias HydraX.Security.Secrets

  alias HydraX.Runtime.{AgentProfile, Helpers, ProviderConfig, ToolPolicy}

  def list_provider_configs do
    ProviderConfig
    |> order_by([provider], desc: provider.enabled, asc: provider.name)
    |> Repo.all()
    |> Enum.map(&decrypt_provider/1)
  end

  def get_provider_config!(id), do: Repo.get!(ProviderConfig, id) |> decrypt_provider()

  def enabled_provider do
    Repo.one(from(provider in ProviderConfig, where: provider.enabled == true, limit: 1))
    |> decrypt_provider()
  end

  def enabled_provider(agent_id, process_type \\ "channel") do
    effective_provider_route(agent_id, process_type).provider
  end

  def effective_provider_route(nil, process_type) do
    effective_provider_route(nil, process_type, [])
  end

  def effective_provider_route(agent_id, process_type) when is_integer(agent_id) do
    effective_provider_route(agent_id, process_type, [])
  end

  def effective_provider_route(nil, _process_type, _opts) do
    provider = enabled_provider()
    %{provider: provider, fallbacks: [], source: if(provider, do: "global", else: "mock")}
  end

  def effective_provider_route(agent_id, process_type, opts) when is_integer(agent_id) do
    agent = Repo.get(AgentProfile, agent_id)
    profile = provider_routing_profile(agent_id)
    override_id = get_in(profile, ["process_overrides", to_string(process_type)])
    default_id = profile["default_provider_id"]

    primary =
      resolve_provider_id(override_id) ||
        resolve_provider_id(default_id) ||
        enabled_provider()

    fallbacks =
      profile["fallback_provider_ids"]
      |> List.wrap()
      |> Enum.map(&resolve_provider_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(primary && &1.id == primary.id))

    {selected_provider, selected_fallbacks, budget_state} =
      maybe_promote_budget_fallback(agent_id, primary, fallbacks, opts)

    %{
      provider: selected_provider,
      fallbacks: selected_fallbacks,
      source:
        budget_state[:source] ||
          route_source(override_id, default_id, selected_provider || primary),
      budget: budget_state,
      warmup: provider_routing_status(agent)
    }
  end

  def provider_routing_profile(nil), do: default_provider_routing_profile()

  def provider_routing_profile(agent_id) when is_integer(agent_id) do
    case Repo.get(AgentProfile, agent_id) do
      nil ->
        default_provider_routing_profile()

      agent ->
        normalize_provider_routing_profile(
          get_in(agent.runtime_state || %{}, ["provider_routing"])
        )
    end
  end

  def save_agent_provider_routing(agent_id, attrs) when is_integer(agent_id) do
    agent = Repo.get!(AgentProfile, agent_id)

    profile =
      agent.runtime_state
      |> Kernel.||(%{})
      |> Map.put("provider_routing", build_provider_routing_profile(attrs, agent))

    agent
    |> AgentProfile.changeset(%{runtime_state: profile})
    |> Repo.update()
  end

  def clear_agent_provider_routing!(agent_id) when is_integer(agent_id) do
    agent = Repo.get!(AgentProfile, agent_id)
    runtime_state = Map.delete(agent.runtime_state || %{}, "provider_routing")

    agent
    |> AgentProfile.changeset(%{runtime_state: runtime_state})
    |> Repo.update!()
  end

  def warm_agent_provider_routing(agent_id, opts \\ []) when is_integer(agent_id) do
    agent = Repo.get!(AgentProfile, agent_id)
    process_type = Keyword.get(opts, :process_type, "channel")
    route = effective_provider_route(agent_id, process_type)
    providers = Enum.reject([route.provider | route.fallbacks], &is_nil/1)
    warmed_at = DateTime.utc_now()

    status =
      case providers do
        [] ->
          %{
            "status" => "mock",
            "process_type" => process_type,
            "warmed_at" => warmed_at,
            "selected_provider_id" => nil,
            "checked_provider_ids" => [],
            "last_error" => nil
          }

        _ ->
          do_warm_providers(providers, process_type, warmed_at, opts)
      end

    runtime_state =
      (agent.runtime_state || %{})
      |> Map.put("provider_routing_status", status)

    {:ok, updated} =
      agent
      |> AgentProfile.changeset(%{runtime_state: runtime_state})
      |> Repo.update()

    {:ok, updated, status}
  end

  def change_provider_config(provider \\ %ProviderConfig{}, attrs \\ %{}) do
    ProviderConfig.changeset(decrypt_provider(provider), attrs)
  end

  def save_provider_config(attrs) when is_map(attrs) do
    save_provider_config(%ProviderConfig{}, attrs)
  end

  def save_provider_config(%ProviderConfig{} = provider, attrs) do
    Repo.transaction(fn ->
      decrypted = decrypt_provider(provider)

      encrypted_attrs =
        attrs
        |> Helpers.normalize_string_keys()
        |> Secrets.encrypt_secret_attrs(decrypted, [:api_key])

      changeset = ProviderConfig.changeset(provider, encrypted_attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> decrypt_provider(record)
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
            workspace_list_enabled: true,
            workspace_read_enabled: true,
            workspace_write_enabled: false,
            http_fetch_enabled: true,
            browser_automation_enabled: false,
            web_search_enabled: true,
            shell_command_enabled: true,
            workspace_write_channels_csv: Enum.join(default_workspace_write_channels(), ","),
            http_fetch_channels_csv: Enum.join(default_network_tool_channels(), ","),
            browser_automation_channels_csv: Enum.join(default_network_tool_channels(), ","),
            web_search_channels_csv: Enum.join(default_network_tool_channels(), ","),
            shell_command_channels_csv: Enum.join(default_shell_channels(), ",")
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
      Helpers.normalize_string_keys(attrs)
      |> Map.put_new("scope", "default")
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
      workspace_list_enabled: Map.get(policy, :workspace_list_enabled, true),
      workspace_read_enabled: Map.get(policy, :workspace_read_enabled, true),
      workspace_write_enabled: Map.get(policy, :workspace_write_enabled, false),
      http_fetch_enabled: Map.get(policy, :http_fetch_enabled, true),
      browser_automation_enabled: Map.get(policy, :browser_automation_enabled, false),
      web_search_enabled: Map.get(policy, :web_search_enabled, true),
      shell_command_enabled: Map.get(policy, :shell_command_enabled, true),
      workspace_write_channels:
        csv_values(policy.workspace_write_channels_csv, default_workspace_write_channels()),
      http_fetch_channels:
        csv_values(policy.http_fetch_channels_csv, default_network_tool_channels()),
      browser_automation_channels:
        csv_values(policy.browser_automation_channels_csv, default_network_tool_channels()),
      web_search_channels:
        csv_values(policy.web_search_channels_csv, default_network_tool_channels()),
      shell_command_channels:
        csv_values(policy.shell_command_channels_csv, default_shell_channels()),
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

  def provider_capabilities(nil), do: provider_module(nil).capabilities()

  def provider_capabilities(%ProviderConfig{} = provider) do
    provider
    |> provider_module()
    |> apply(:capabilities, [])
  end

  def provider_health(provider, opts \\ [])
  def provider_health(nil, opts), do: provider_module(nil).healthcheck(nil, opts)

  def provider_health(%ProviderConfig{} = provider, opts) do
    provider
    |> provider_module()
    |> apply(:healthcheck, [provider, opts])
  end

  # -- Private helpers --

  defp do_warm_providers([], process_type, warmed_at, _opts) do
    %{
      "status" => "degraded",
      "process_type" => process_type,
      "warmed_at" => warmed_at,
      "selected_provider_id" => nil,
      "checked_provider_ids" => [],
      "last_error" => "no provider could be warmed"
    }
  end

  defp do_warm_providers([provider | rest], process_type, warmed_at, opts) do
    case test_provider_config(provider, opts) do
      {:ok, result} ->
        %{
          "status" => "ready",
          "process_type" => process_type,
          "warmed_at" => warmed_at,
          "selected_provider_id" => provider.id,
          "selected_provider_name" => provider.name,
          "checked_provider_ids" => [provider.id],
          "last_error" => nil,
          "probe_content" => result.content
        }

      {:error, reason} ->
        next = do_warm_providers(rest, process_type, warmed_at, opts)

        case next["status"] do
          "ready" ->
            Map.update!(next, "checked_provider_ids", &[provider.id | &1])

          _ ->
            %{
              "status" => "degraded",
              "process_type" => process_type,
              "warmed_at" => warmed_at,
              "selected_provider_id" => nil,
              "checked_provider_ids" => [provider.id],
              "last_error" => inspect(reason)
            }
        end
    end
  end

  defp decrypt_provider(nil), do: nil

  defp decrypt_provider(%ProviderConfig{} = provider),
    do: Secrets.decrypt_fields(provider, [:api_key])

  defp provider_routing_status(nil), do: default_provider_routing_status()

  defp provider_routing_status(agent) do
    Map.get(
      agent.runtime_state || %{},
      "provider_routing_status",
      default_provider_routing_status()
    )
  end

  defp default_provider_routing_status do
    %{
      "status" => "cold",
      "process_type" => "channel",
      "warmed_at" => nil,
      "selected_provider_id" => nil,
      "checked_provider_ids" => [],
      "last_error" => nil
    }
  end

  defp default_provider_routing_profile do
    %{
      "default_provider_id" => nil,
      "fallback_provider_ids" => [],
      "process_overrides" => %{}
    }
  end

  defp build_provider_routing_profile(attrs, agent) do
    attrs = Helpers.normalize_string_keys(attrs)

    current =
      normalize_provider_routing_profile(get_in(agent.runtime_state || %{}, ["provider_routing"]))

    %{
      "default_provider_id" =>
        persisted_provider_id(attrs, "default_provider_id", current["default_provider_id"]),
      "fallback_provider_ids" =>
        persisted_provider_ids(
          attrs,
          "fallback_provider_ids_csv",
          current["fallback_provider_ids"]
        ),
      "process_overrides" => %{
        "channel" =>
          persisted_provider_id(
            attrs,
            "channel_provider_id",
            get_in(current, ["process_overrides", "channel"])
          ),
        "cortex" =>
          persisted_provider_id(
            attrs,
            "cortex_provider_id",
            get_in(current, ["process_overrides", "cortex"])
          ),
        "compactor" =>
          persisted_provider_id(
            attrs,
            "compactor_provider_id",
            get_in(current, ["process_overrides", "compactor"])
          ),
        "scheduler" =>
          persisted_provider_id(
            attrs,
            "scheduler_provider_id",
            get_in(current, ["process_overrides", "scheduler"])
          )
      }
    }
  end

  defp normalize_provider_routing_profile(nil), do: default_provider_routing_profile()

  defp normalize_provider_routing_profile(profile) when is_map(profile) do
    %{
      "default_provider_id" => normalize_provider_id(profile["default_provider_id"]),
      "fallback_provider_ids" => normalize_provider_ids(profile["fallback_provider_ids"]),
      "process_overrides" => %{
        "channel" => normalize_provider_id(get_in(profile, ["process_overrides", "channel"])),
        "cortex" => normalize_provider_id(get_in(profile, ["process_overrides", "cortex"])),
        "compactor" => normalize_provider_id(get_in(profile, ["process_overrides", "compactor"])),
        "scheduler" => normalize_provider_id(get_in(profile, ["process_overrides", "scheduler"]))
      }
    }
  end

  defp persisted_provider_id(attrs, key, fallback) do
    if Map.has_key?(attrs, key) do
      normalize_provider_id(Map.get(attrs, key))
    else
      fallback
    end
  end

  defp persisted_provider_ids(attrs, key, fallback) do
    if Map.has_key?(attrs, key) do
      normalize_provider_ids(Map.get(attrs, key))
    else
      fallback
    end
  end

  defp normalize_provider_id(nil), do: nil
  defp normalize_provider_id(""), do: nil
  defp normalize_provider_id(value) when is_integer(value), do: value

  defp normalize_provider_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp normalize_provider_ids(nil), do: []
  defp normalize_provider_ids(""), do: []

  defp normalize_provider_ids(values) when is_list(values),
    do: Enum.map(values, &normalize_provider_id/1) |> Enum.reject(&is_nil/1)

  defp normalize_provider_ids(csv) when is_binary(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&normalize_provider_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp resolve_provider_id(nil), do: nil
  defp resolve_provider_id(id) when is_integer(id), do: Repo.get(ProviderConfig, id)

  defp route_source(override_id, _default_id, provider)
       when not is_nil(override_id) and not is_nil(provider),
       do: "process_override"

  defp route_source(_override_id, default_id, provider)
       when not is_nil(default_id) and not is_nil(provider),
       do: "agent_default"

  defp route_source(_override_id, _default_id, provider) when not is_nil(provider), do: "global"
  defp route_source(_override_id, _default_id, _provider), do: "mock"

  defp maybe_promote_budget_fallback(agent_id, primary, fallbacks, opts) do
    estimated_tokens = Keyword.get(opts, :estimated_tokens, 0)
    conversation_id = Keyword.get(opts, :conversation_id)

    cond do
      is_nil(primary) or fallbacks == [] or estimated_tokens <= 0 ->
        {primary, fallbacks, %{estimated_tokens: estimated_tokens, warnings: [], source: nil}}

      true ->
        case Budget.preflight(agent_id, conversation_id, estimated_tokens) do
          {:ok, %{warnings: warnings, usage: usage}} when warnings != [] ->
            promoted = hd(fallbacks)
            remaining = Enum.reject([primary | tl(fallbacks)], &is_nil/1)

            {promoted, remaining,
             %{
               estimated_tokens: estimated_tokens,
               warnings: warnings,
               usage: usage,
               source: "budget:" <> Enum.map_join(warnings, ",", &to_string/1)
             }}

          {:ok, %{warnings: warnings, usage: usage}} ->
            {primary, fallbacks,
             %{estimated_tokens: estimated_tokens, warnings: warnings, usage: usage, source: nil}}

          {:error, %{reason: reason, usage: usage}} ->
            {primary, fallbacks,
             %{
               estimated_tokens: estimated_tokens,
               warnings: [reason],
               usage: usage,
               source: nil
             }}
        end
    end
  end

  defp provider_module(%ProviderConfig{kind: "openai_compatible"}),
    do: HydraX.LLM.Providers.OpenAICompatible

  defp provider_module(%ProviderConfig{kind: "anthropic"}), do: HydraX.LLM.Providers.Anthropic
  defp provider_module(nil), do: HydraX.LLM.Providers.Mock

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

  defp default_workspace_write_channels, do: ~w(control_plane cli scheduler)
  defp default_network_tool_channels, do: ~w(control_plane cli scheduler)
  defp default_shell_channels, do: ~w(control_plane cli scheduler)
end
