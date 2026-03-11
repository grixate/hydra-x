defmodule HydraX.Runtime.MCPServers do
  @moduledoc """
  Persisted MCP server registry and health probing.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.{AgentMCPServer, AgentProfile, Helpers, MCPServerConfig}
  alias HydraX.Security.Secrets

  def list_mcp_servers do
    MCPServerConfig
    |> order_by([config], desc: config.enabled, asc: config.name)
    |> Repo.all()
    |> Enum.map(&decrypt_config/1)
  end

  def get_mcp_server!(id), do: Repo.get!(MCPServerConfig, id) |> decrypt_config()

  def enabled_mcp_servers do
    list_mcp_servers()
    |> Enum.filter(& &1.enabled)
  end

  def list_agent_mcp_servers(agent_id) when is_integer(agent_id) do
    AgentMCPServer
    |> where([binding], binding.agent_id == ^agent_id)
    |> join(:inner, [binding], config in assoc(binding, :mcp_server_config))
    |> preload([_binding, config], mcp_server_config: config)
    |> order_by([binding, config], desc: binding.enabled, asc: config.name)
    |> Repo.all()
    |> Enum.map(&decrypt_binding/1)
  end

  def enabled_mcp_servers(agent_id) when is_integer(agent_id) do
    list_agent_mcp_servers(agent_id)
    |> Enum.filter(&(&1.enabled && &1.mcp_server_config.enabled))
  end

  def get_agent_mcp_server!(id) do
    AgentMCPServer
    |> Repo.get!(id)
    |> Repo.preload(:mcp_server_config)
    |> decrypt_binding()
  end

  def change_mcp_server(config \\ %MCPServerConfig{}, attrs \\ %{}) do
    MCPServerConfig.changeset(decrypt_config(config), attrs)
  end

  def save_mcp_server(attrs) when is_map(attrs), do: save_mcp_server(%MCPServerConfig{}, attrs)

  def save_mcp_server(%MCPServerConfig{} = config, attrs) do
    Repo.transaction(fn ->
      decrypted = decrypt_config(config)

      encrypted_attrs =
        attrs
        |> Helpers.normalize_string_keys()
        |> Secrets.encrypt_secret_attrs(decrypted, [:auth_token])

      record =
        config
        |> MCPServerConfig.changeset(encrypted_attrs)
        |> Repo.insert_or_update()
        |> case do
          {:ok, record} -> decrypt_config(record)
          {:error, changeset} -> Repo.rollback(changeset)
        end

      Helpers.audit_operator_action(
        "Saved MCP server #{record.name}",
        metadata: %{"mcp_server_id" => record.id, "transport" => record.transport}
      )

      record
    end)
    |> Helpers.unwrap_transaction()
  end

  def delete_mcp_server!(id) do
    config = get_mcp_server!(id)
    Repo.delete!(config)

    Helpers.audit_operator_action(
      "Deleted MCP server #{config.name}",
      metadata: %{"mcp_server_id" => config.id, "transport" => config.transport}
    )

    config
  end

  def mcp_statuses do
    list_mcp_servers()
    |> Enum.map(&server_status/1)
  end

  def agent_mcp_statuses do
    status_map =
      list_mcp_servers()
      |> Enum.map(fn config -> {config.id, server_status(config)} end)
      |> Map.new()

    AgentProfile
    |> order_by([agent], asc: agent.name, asc: agent.slug)
    |> Repo.all()
    |> Enum.map(&agent_mcp_status(&1, status_map))
  end

  def agent_mcp_statuses(agent_id) when is_integer(agent_id) do
    status_map =
      list_mcp_servers()
      |> Enum.map(fn config -> {config.id, server_status(config)} end)
      |> Map.new()

    AgentProfile
    |> Repo.get!(agent_id)
    |> agent_mcp_status(status_map)
  end

  def test_mcp_server(%MCPServerConfig{} = config, opts \\ []) do
    probe(config, opts)
  end

  def invoke_agent_mcp(agent_id, action, params, opts \\ []) when is_integer(agent_id) do
    server_filter =
      opts
      |> Keyword.get(:server)
      |> normalize_filter()

    results =
      list_agent_mcp_servers(agent_id)
      |> Enum.filter(&(&1.enabled && &1.mcp_server_config.enabled))
      |> Enum.filter(fn binding ->
        is_nil(server_filter) or matches_filter?(binding.mcp_server_config, server_filter)
      end)
      |> Enum.map(fn binding ->
        invoke_binding(binding, action, params, opts)
      end)

    {:ok,
     %{
       agent_id: agent_id,
       action: action,
       count: length(results),
       results: results
     }}
  end

  def list_agent_mcp_actions(agent_id, opts \\ []) when is_integer(agent_id) do
    server_filter =
      opts
      |> Keyword.get(:server)
      |> normalize_filter()

    results =
      list_agent_mcp_servers(agent_id)
      |> Enum.filter(&(&1.enabled && &1.mcp_server_config.enabled))
      |> Enum.filter(fn binding ->
        is_nil(server_filter) or matches_filter?(binding.mcp_server_config, server_filter)
      end)
      |> Enum.map(fn binding ->
        list_binding_actions(binding, opts)
      end)

    {:ok,
     %{
       agent_id: agent_id,
       count: length(results),
       results: results
     }}
  end

  def mcp_prompt_context do
    enabled_mcp_servers()
    |> Enum.map(fn config ->
      status =
        case server_status(config) do
          %{status: :ok} -> "healthy"
          %{status: :warn} -> "degraded"
        end

      descriptor =
        case config.transport do
          "stdio" ->
            command = config.command || "unknown"
            "stdio command `#{command}`"

          "http" ->
            "HTTP endpoint `#{build_health_url(config)}`"

          other ->
            other
        end

      "- #{config.name}: #{descriptor} (#{status})"
    end)
    |> Enum.join("\n")
  end

  def mcp_prompt_context(agent_id) when is_integer(agent_id) do
    enabled_mcp_servers(agent_id)
    |> Enum.map(fn binding ->
      actions =
        get_in(binding.mcp_server_config.metadata || %{}, ["actions"])
        |> case do
          values when is_list(values) and values != [] ->
            " actions #{Enum.join(Enum.take(values, 3), ", ")}"

          _ ->
            ""
        end

      mcp_prompt_line(binding.mcp_server_config) <> actions
    end)
    |> Enum.join("\n")
  end

  def refresh_agent_mcp_servers(agent_id) when is_integer(agent_id) do
    agent = Repo.get!(AgentProfile, agent_id)
    configs = list_mcp_servers()

    Repo.transaction(fn ->
      existing =
        AgentMCPServer
        |> where([binding], binding.agent_id == ^agent.id)
        |> Repo.all()
        |> Map.new(&{&1.mcp_server_config_id, &1})

      kept_ids =
        Enum.map(configs, fn config ->
          record = Map.get(existing, config.id, %AgentMCPServer{})

          enabled =
            existing
            |> Map.get(config.id, %AgentMCPServer{enabled: true})
            |> Map.get(:enabled)

          attrs = %{
            agent_id: agent.id,
            mcp_server_config_id: config.id,
            enabled: enabled,
            metadata: %{"name" => config.name, "transport" => config.transport}
          }

          {:ok, saved} =
            record
            |> AgentMCPServer.changeset(attrs)
            |> Repo.insert_or_update()

          saved.mcp_server_config_id
        end)

      AgentMCPServer
      |> where(
        [binding],
        binding.agent_id == ^agent.id and binding.mcp_server_config_id not in ^kept_ids
      )
      |> Repo.delete_all()

      list_agent_mcp_servers(agent.id)
    end)
    |> Helpers.unwrap_transaction()
    |> case do
      {:ok, bindings} ->
        Helpers.audit_operator_action(
          "Refreshed MCP bindings for #{agent.slug}",
          agent: agent,
          metadata: %{"mcp_binding_count" => length(bindings)}
        )

        {:ok, bindings}

      other ->
        other
    end
  end

  def enable_agent_mcp_server!(id), do: set_agent_mcp_enabled!(id, true)
  def disable_agent_mcp_server!(id), do: set_agent_mcp_enabled!(id, false)

  defp server_status(config) do
    case probe(config, []) do
      {:ok, result} ->
        %{
          id: config.id,
          name: config.name,
          transport: config.transport,
          enabled: config.enabled,
          status: :ok,
          detail: result.detail
        }

      {:error, reason} ->
        %{
          id: config.id,
          name: config.name,
          transport: config.transport,
          enabled: config.enabled,
          status: :warn,
          detail: format_probe_error(reason)
        }
    end
  end

  defp agent_mcp_status(%AgentProfile{} = agent, status_map) do
    bindings =
      list_agent_mcp_servers(agent.id)
      |> Enum.map(fn binding ->
        server = binding.mcp_server_config
        status = Map.get(status_map, server.id) || server_status(server)

        %{
          id: binding.id,
          enabled: binding.enabled,
          server_id: server.id,
          server_name: server.name,
          transport: server.transport,
          server_enabled: server.enabled,
          status: status.status,
          detail: status.detail
        }
      end)

    %{
      agent_id: agent.id,
      agent_name: agent.name,
      agent_slug: agent.slug,
      total_bindings: length(bindings),
      enabled_bindings: Enum.count(bindings, & &1.enabled),
      healthy_bindings: Enum.count(bindings, &(&1.enabled && &1.status == :ok)),
      bindings: bindings
    }
  end

  defp probe(%MCPServerConfig{enabled: false} = config, _opts) do
    {:error, {:disabled, "#{config.name} is disabled"}}
  end

  defp probe(%MCPServerConfig{transport: "stdio"} = config, _opts) do
    executable =
      cond do
        is_binary(config.command) and String.contains?(config.command, "/") and
            File.exists?(config.command) ->
          config.command

        is_binary(config.command) ->
          System.find_executable(config.command)

        true ->
          nil
      end

    case executable do
      nil ->
        {:error, :command_not_found}

      path ->
        {:ok,
         %{
           transport: "stdio",
           detail: "command #{path} available",
           metadata: %{command: config.command, cwd: config.cwd}
         }}
    end
  end

  defp probe(%MCPServerConfig{transport: "http"} = config, opts) do
    request_fn =
      Keyword.get(opts, :request_fn) || Application.get_env(:hydra_x, :mcp_http_request_fn) ||
        (&Req.get/1)

    retries = Keyword.get(opts, :retry_limit, config.retry_limit || 0)
    do_http_probe(config, request_fn, retries)
  end

  defp do_http_probe(config, request_fn, retries_left) do
    url = build_health_url(config)

    headers =
      [{"accept", "application/json"}]
      |> maybe_add_auth_header(config.auth_token)

    case request_fn.(url: url, headers: headers) do
      {:ok, %{status: status}} when status in 200..399 ->
        {:ok,
         %{
           transport: "http",
           detail: "HTTP #{status} from #{url}",
           metadata: %{url: url, status: status}
         }}

      {:ok, %{status: _status}} when retries_left > 0 ->
        do_http_probe(config, request_fn, retries_left - 1)

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, _reason} when retries_left > 0 ->
        do_http_probe(config, request_fn, retries_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp invoke_binding(binding, action, params, opts) do
    config = binding.mcp_server_config

    case invoke_server(config, action, params, opts) do
      {:ok, result} ->
        %{
          id: binding.id,
          server_id: config.id,
          name: config.name,
          transport: config.transport,
          status: "ok",
          result: result
        }

      {:error, reason} ->
        %{
          id: binding.id,
          server_id: config.id,
          name: config.name,
          transport: config.transport,
          status: "warn",
          detail: format_probe_error(reason)
        }
    end
  end

  defp list_binding_actions(binding, opts) do
    config = binding.mcp_server_config

    case list_server_actions(config, opts) do
      {:ok, actions} ->
        %{
          id: binding.id,
          server_id: config.id,
          name: config.name,
          transport: config.transport,
          status: "ok",
          actions: actions
        }

      {:error, reason} ->
        %{
          id: binding.id,
          server_id: config.id,
          name: config.name,
          transport: config.transport,
          status: "warn",
          detail: format_probe_error(reason)
        }
    end
  end

  defp invoke_server(%MCPServerConfig{enabled: false} = config, _action, _params, _opts) do
    {:error, {:disabled, "#{config.name} is disabled"}}
  end

  defp invoke_server(%MCPServerConfig{transport: "stdio"}, _action, _params, _opts) do
    {:error, :stdio_invoke_not_supported}
  end

  defp invoke_server(%MCPServerConfig{transport: "http"} = config, action, params, opts) do
    request_fn =
      Keyword.get(opts, :request_fn) || Application.get_env(:hydra_x, :mcp_http_request_fn) ||
        (&Req.post/1)

    path =
      get_in(config.metadata || %{}, ["invoke_path"])
      |> Helpers.blank_to_nil()
      |> Kernel.||("/invoke")

    url =
      config.url
      |> URI.parse()
      |> URI.merge(path)
      |> URI.to_string()

    headers =
      [
        {"accept", "application/json"},
        {"content-type", "application/json"}
      ]
      |> maybe_add_auth_header(config.auth_token)

    payload = %{action: action, params: params || %{}}

    case request_fn.(url: url, headers: headers, json: payload) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok,
         %{
           url: url,
           action: action,
           status: status,
           body: normalize_invoke_body(body)
         }}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_server_actions(%MCPServerConfig{enabled: false} = config, _opts) do
    {:error, {:disabled, "#{config.name} is disabled"}}
  end

  defp list_server_actions(%MCPServerConfig{transport: "stdio"}, _opts) do
    {:error, :stdio_action_catalog_not_supported}
  end

  defp list_server_actions(%MCPServerConfig{transport: "http"} = config, opts) do
    request_fn =
      Keyword.get(opts, :request_fn) || Application.get_env(:hydra_x, :mcp_http_request_fn) ||
        (&Req.get/1)

    path =
      get_in(config.metadata || %{}, ["actions_path"])
      |> Helpers.blank_to_nil()
      |> Kernel.||("/actions")

    url =
      config.url
      |> URI.parse()
      |> URI.merge(path)
      |> URI.to_string()

    headers =
      [{"accept", "application/json"}]
      |> maybe_add_auth_header(config.auth_token)

    case request_fn.(url: url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        actions = normalize_action_list(body)
        maybe_cache_server_actions(config, actions)
        {:ok, actions}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_health_url(config) do
    healthcheck_path =
      config.healthcheck_path
      |> Helpers.blank_to_nil()
      |> Kernel.||("/health")

    base = URI.parse(config.url)
    URI.merge(base, healthcheck_path) |> URI.to_string()
  end

  defp maybe_add_auth_header(headers, nil), do: headers
  defp maybe_add_auth_header(headers, ""), do: headers

  defp maybe_add_auth_header(headers, token),
    do: [{"authorization", "Bearer " <> token} | headers]

  defp format_probe_error({:disabled, message}), do: message
  defp format_probe_error(:command_not_found), do: "command not found"
  defp format_probe_error(:stdio_invoke_not_supported), do: "stdio invoke not supported"
  defp format_probe_error(:stdio_action_catalog_not_supported), do: "stdio action catalog not supported"
  defp format_probe_error({:http_status, status}), do: "unexpected HTTP #{status}"
  defp format_probe_error(reason), do: inspect(reason)

  defp normalize_filter(nil), do: nil
  defp normalize_filter(""), do: nil
  defp normalize_filter(value), do: value |> to_string() |> String.downcase()

  defp matches_filter?(config, filter) do
    [config.name, get_in(config.metadata || %{}, ["slug"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase(to_string(&1)))
    |> Enum.any?(&String.contains?(&1, filter))
  end

  defp normalize_invoke_body(body) when is_binary(body), do: body
  defp normalize_invoke_body(body) when is_map(body), do: body
  defp normalize_invoke_body(body) when is_list(body), do: body
  defp normalize_invoke_body(body), do: inspect(body)

  defp normalize_action_list(%{"actions" => actions}) when is_list(actions),
    do: Enum.map(actions, &normalize_action_name/1) |> Enum.reject(&is_nil/1)

  defp normalize_action_list(%{actions: actions}) when is_list(actions),
    do: Enum.map(actions, &normalize_action_name/1) |> Enum.reject(&is_nil/1)

  defp normalize_action_list(actions) when is_list(actions),
    do: Enum.map(actions, &normalize_action_name/1) |> Enum.reject(&is_nil/1)

  defp normalize_action_list(_body), do: []

  defp normalize_action_name(%{"name" => name}) when is_binary(name), do: name
  defp normalize_action_name(%{name: name}) when is_binary(name), do: name
  defp normalize_action_name(name) when is_binary(name), do: name
  defp normalize_action_name(_value), do: nil

  defp maybe_cache_server_actions(%MCPServerConfig{} = config, actions) when is_list(actions) do
    metadata =
      (config.metadata || %{})
      |> Map.put("actions", actions)
      |> Map.put("actions_cataloged_at", DateTime.utc_now())

    if metadata == (config.metadata || %{}) do
      :ok
    else
      config
      |> MCPServerConfig.changeset(%{metadata: metadata})
      |> Repo.update()

      :ok
    end
  end

  defp decrypt_config(nil), do: nil

  defp decrypt_config(%MCPServerConfig{} = config),
    do: Secrets.decrypt_fields(config, [:auth_token])

  defp decrypt_binding(%AgentMCPServer{} = binding) do
    binding
    |> Repo.preload(:mcp_server_config)
    |> Map.update!(:mcp_server_config, &decrypt_config/1)
  end

  defp mcp_prompt_line(config) do
    status =
      case server_status(config) do
        %{status: :ok} -> "healthy"
        %{status: :warn} -> "degraded"
      end

    descriptor =
      case config.transport do
        "stdio" ->
          command = config.command || "unknown"
          "stdio command `#{command}`"

        "http" ->
          "HTTP endpoint `#{build_health_url(config)}`"

        other ->
          other
      end

    "- #{config.name}: #{descriptor} (#{status})"
  end

  defp set_agent_mcp_enabled!(id, enabled) do
    binding = get_agent_mcp_server!(id)

    {:ok, updated} =
      binding
      |> AgentMCPServer.changeset(%{enabled: enabled})
      |> Repo.update()
      |> case do
        {:ok, saved} -> {:ok, decrypt_binding(saved)}
        other -> other
      end

    agent = Repo.get!(AgentProfile, updated.agent_id)

    Helpers.audit_operator_action(
      "#{if(enabled, do: "Enabled", else: "Disabled")} MCP #{updated.mcp_server_config.name} for #{agent.slug}",
      agent: agent,
      metadata: %{
        "agent_mcp_id" => updated.id,
        "mcp_server_id" => updated.mcp_server_config_id,
        "mcp_name" => updated.mcp_server_config.name
      }
    )

    updated
  end
end
