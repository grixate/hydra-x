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

    refresh? = Keyword.get(opts, :refresh, false)

    results =
      list_agent_mcp_servers(agent_id)
      |> Enum.filter(&(&1.enabled && &1.mcp_server_config.enabled))
      |> Enum.filter(fn binding ->
        is_nil(server_filter) or matches_filter?(binding.mcp_server_config, server_filter)
      end)
      |> Enum.map(fn binding ->
        list_binding_actions(binding, Keyword.put(opts, :refresh, refresh?))
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
            metadata: binding_metadata(config)
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

  def mcp_posture(%MCPServerConfig{} = config) do
    metadata = config.metadata || %{}
    status = server_status(config)

    rollout_state =
      cond do
        not config.enabled -> "disabled"
        metadata["rollout_state"] in ["canary", "staged"] -> metadata["rollout_state"]
        true -> "stable"
      end

    %{
      version: metadata["version"],
      compatibility_posture: if(status.status == :ok, do: "compatible", else: "degraded"),
      health_posture: status.status,
      enablement_risk: mcp_enablement_risk(config),
      rollout_state: rollout_state,
      last_promoted_at: metadata["last_promoted_at"]
    }
  end

  def mcp_enablement_risk(%MCPServerConfig{} = config) do
    cond do
      config.transport == "http" and is_nil(config.auth_token) -> "high"
      config.transport == "http" -> "medium"
      true -> "low"
    end
  end

  def promote_mcp_server!(id) do
    config = get_mcp_server!(id)

    new_metadata =
      (config.metadata || %{})
      |> Map.put("rollout_state", "stable")
      |> Map.put("last_promoted_at", DateTime.utc_now() |> DateTime.to_iso8601())

    {:ok, updated} =
      config
      |> MCPServerConfig.changeset(%{metadata: new_metadata})
      |> Repo.update()

    Helpers.audit_operator_action(
      "Promoted MCP server #{updated.name} to stable",
      metadata: %{"mcp_server_id" => updated.id, "rollout_state" => "stable"}
    )

    {:ok, updated}
  end

  def stage_mcp_server!(id, stage \\ "canary") when stage in ["canary", "staged"] do
    config = get_mcp_server!(id)

    new_metadata =
      (config.metadata || %{})
      |> Map.put("rollout_state", stage)
      |> Map.put("staged_at", DateTime.utc_now() |> DateTime.to_iso8601())

    {:ok, updated} =
      config
      |> MCPServerConfig.changeset(%{metadata: new_metadata})
      |> Repo.update()

    Helpers.audit_operator_action(
      "Staged MCP server #{updated.name} as #{stage}",
      metadata: %{"mcp_server_id" => updated.id, "rollout_state" => stage}
    )

    {:ok, updated}
  end

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
      {:ok, catalog} ->
        %{
          id: binding.id,
          server_id: config.id,
          name: config.name,
          transport: config.transport,
          status: "ok",
          actions: catalog_action_names(catalog),
          action_catalog: catalog,
          catalog_source: catalog_source(catalog)
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

  defp invoke_server(%MCPServerConfig{transport: "stdio"} = config, action, params, opts) do
    action_descriptor = find_cached_action_descriptor(config, action)

    with {:ok, %{output: output, status: status}} <-
           run_stdio_request(
             config,
             %{
               "op" => "invoke",
               "action" => action,
               "params" => params || %{}
             },
             opts
           ),
         {:ok, body} <- decode_stdio_payload(output),
         true <- status == 0 or {:error, {:stdio_exit_status, status, output}} do
      {:ok, normalize_stdio_invoke_result(config, action, status, body, action_descriptor)}
    end
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
    action_descriptor = find_cached_action_descriptor(config, action)

    case request_fn.(url: url, headers: headers, json: payload) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, normalize_http_invoke_result(url, action, status, body, action_descriptor)}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_server_actions(%MCPServerConfig{enabled: false} = config, _opts) do
    {:error, {:disabled, "#{config.name} is disabled"}}
  end

  defp list_server_actions(%MCPServerConfig{transport: "stdio"} = config, opts) do
    cond do
      Keyword.get(opts, :refresh, false) ->
        with {:ok, %{output: output, status: status}} <-
               run_stdio_request(config, %{"op" => "actions"}, opts),
             {:ok, catalog_body} <- decode_stdio_action_catalog(output),
             true <- status == 0 or {:error, {:stdio_exit_status, status, output}} do
          catalog =
            normalize_action_catalog(catalog_body, build_action_catalog_url(config), "live")

          maybe_cache_server_actions(config, catalog)
          {:ok, catalog}
        end

      cached = cached_action_catalog(config) ->
        {:ok, cached}

      true ->
        {:ok, empty_action_catalog(config)}
    end
  end

  defp list_server_actions(%MCPServerConfig{transport: "http"} = config, opts) do
    cond do
      Keyword.get(opts, :refresh, false) ->
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
            catalog = normalize_action_catalog(body, url, "live")
            maybe_cache_server_actions(config, catalog)
            {:ok, catalog}

          {:ok, %{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            {:error, reason}
        end

      cached = cached_action_catalog(config) ->
        {:ok, cached}

      true ->
        {:ok, empty_action_catalog(config)}
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
  defp format_probe_error({:http_status, status}), do: "unexpected HTTP #{status}"
  defp format_probe_error({:stdio_exit_status, status, _output}), do: "stdio exit #{status}"
  defp format_probe_error({:stdio_invalid_json, reason}), do: "stdio invalid json: #{reason}"
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

  defp normalize_action_catalog(%{"actions" => actions}, url, source) when is_list(actions),
    do: build_action_catalog(actions, url, source)

  defp normalize_action_catalog(%{actions: actions}, url, source) when is_list(actions),
    do: build_action_catalog(actions, url, source)

  defp normalize_action_catalog(actions, url, source) when is_list(actions),
    do: build_action_catalog(actions, url, source)

  defp normalize_action_catalog(_body, url, source),
    do: empty_action_catalog(%{url: url, source: source})

  defp build_action_catalog(actions, url, source) do
    normalized =
      actions
      |> Enum.map(&normalize_action_descriptor/1)
      |> Enum.reject(&is_nil/1)

    %{
      "actions" => normalized,
      "names" => Enum.map(normalized, & &1["name"]),
      "cataloged_at" => DateTime.utc_now(),
      "source" => source,
      "url" => url
    }
  end

  defp empty_action_catalog(config_or_meta) do
    %{
      "actions" => [],
      "names" => [],
      "cataloged_at" => DateTime.utc_now(),
      "source" => Map.get(config_or_meta, :source) || "cache",
      "url" =>
        Map.get(config_or_meta, :url) ||
          Map.get(config_or_meta, "url") ||
          build_action_catalog_url(config_or_meta)
    }
  end

  defp normalize_action_descriptor(%{"name" => name} = action) when is_binary(name) do
    %{
      "name" => name,
      "title" => action["title"],
      "description" => action["description"],
      "input_schema" => action["input_schema"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_action_descriptor(%{name: name} = action) when is_binary(name) do
    %{
      "name" => name,
      "title" => action[:title],
      "description" => action[:description],
      "input_schema" => action[:input_schema]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_action_descriptor(name) when is_binary(name), do: %{"name" => name}
  defp normalize_action_descriptor(_value), do: nil

  defp maybe_cache_server_actions(%MCPServerConfig{} = config, catalog) when is_map(catalog) do
    metadata =
      (config.metadata || %{})
      |> Map.put("actions", catalog["names"] || [])
      |> Map.put("action_catalog", catalog)
      |> Map.put("actions_cataloged_at", catalog["cataloged_at"] || DateTime.utc_now())

    if metadata == (config.metadata || %{}) do
      :ok
    else
      config
      |> MCPServerConfig.changeset(%{metadata: metadata})
      |> Repo.update()

      :ok
    end
  end

  defp binding_metadata(config) do
    %{
      "name" => config.name,
      "transport" => config.transport,
      "actions" => get_in(config.metadata || %{}, ["actions"]) || [],
      "action_catalog" => get_in(config.metadata || %{}, ["action_catalog"])
    }
  end

  defp cached_action_catalog(%MCPServerConfig{} = config) do
    case get_in(config.metadata || %{}, ["action_catalog"]) do
      %{"actions" => _actions} = catalog ->
        catalog

      %{actions: _actions} = catalog ->
        catalog
        |> Enum.map(fn {key, value} -> {to_string(key), value} end)
        |> Map.new()

      _ ->
        nil
    end
  end

  defp catalog_action_names(%{"names" => names}) when is_list(names), do: names
  defp catalog_action_names(%{names: names}) when is_list(names), do: names
  defp catalog_action_names(_catalog), do: []

  defp catalog_source(%{"source" => source}) when is_binary(source), do: source
  defp catalog_source(%{source: source}) when is_binary(source), do: source
  defp catalog_source(_catalog), do: "cache"

  defp find_cached_action_descriptor(%MCPServerConfig{} = config, action) do
    cached_action_catalog(config)
    |> case do
      nil ->
        nil

      catalog ->
        Enum.find(catalog["actions"] || [], fn entry ->
          entry["name"] == action
        end)
    end
  end

  defp normalize_http_invoke_result(url, action, status, body, action_descriptor) do
    normalized_body = normalize_invoke_body(body)

    %{
      transport: "http_mcp_v1",
      ok: true,
      url: url,
      action: action,
      status: status,
      data: extract_invoke_data(normalized_body),
      text: extract_invoke_text(normalized_body),
      body: normalized_body,
      action_descriptor: action_descriptor
    }
  end

  defp normalize_stdio_invoke_result(config, action, status, body, action_descriptor) do
    normalized_body = normalize_invoke_body(body)

    %{
      transport: "stdio_mcp_v1",
      ok: true,
      command: config.command,
      cwd: config.cwd,
      action: action,
      status: status,
      data: extract_invoke_data(normalized_body),
      text: extract_invoke_text(normalized_body),
      body: normalized_body,
      action_descriptor: action_descriptor
    }
  end

  defp extract_invoke_data(%{"data" => data}), do: data
  defp extract_invoke_data(%{data: data}), do: data
  defp extract_invoke_data(%{"result" => data}), do: data
  defp extract_invoke_data(%{result: data}), do: data
  defp extract_invoke_data(body), do: body

  defp extract_invoke_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_invoke_text(%{text: text}) when is_binary(text), do: text
  defp extract_invoke_text(body) when is_binary(body), do: body
  defp extract_invoke_text(_body), do: nil

  defp build_action_catalog_url(%MCPServerConfig{} = config) do
    case config.transport do
      "stdio" ->
        "stdio://" <> (config.command || config.name || "unknown")

      _ ->
        path =
          get_in(config.metadata || %{}, ["actions_path"])
          |> Helpers.blank_to_nil()
          |> Kernel.||("/actions")

        config.url
        |> URI.parse()
        |> URI.merge(path)
        |> URI.to_string()
    end
  end

  defp build_action_catalog_url(%{url: url}) when is_binary(url), do: url
  defp build_action_catalog_url(_config), do: nil

  defp run_stdio_request(%MCPServerConfig{} = config, payload, opts) do
    runner =
      Keyword.get(opts, :runner) || Application.get_env(:hydra_x, :mcp_stdio_runner) ||
        (&System.cmd/3)

    request =
      payload
      |> Jason.encode!()

    args =
      config.args_csv
      |> Helpers.blank_to_nil()
      |> case do
        nil -> []
        csv -> csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      end

    case runner.(config.command, args, cd: config.cwd, input: request, stderr_to_stdout: true) do
      {output, status} when is_binary(output) and is_integer(status) ->
        {:ok, %{output: output, status: status}}

      {:ok, %{output: output, status: status}}
      when is_binary(output) and is_integer(status) ->
        {:ok, %{output: output, status: status}}

      {:ok, %{stdout: output, status: status}}
      when is_binary(output) and is_integer(status) ->
        {:ok, %{output: output, status: status}}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:stdio_invalid_result, other}}
    end
  end

  defp decode_stdio_payload(output) when is_binary(output) do
    output
    |> String.trim()
    |> case do
      "" ->
        {:ok, %{}}

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, {:stdio_invalid_json, Exception.message(reason)}}
        end
    end
  end

  defp decode_stdio_payload(body) when is_map(body) or is_list(body), do: {:ok, body}
  defp decode_stdio_payload(body), do: {:ok, body}

  defp decode_stdio_action_catalog(output) do
    case decode_stdio_payload(output) do
      {:ok, body} when is_binary(body) ->
        actions =
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, actions}

      {:error, {:stdio_invalid_json, _reason}} when is_binary(output) ->
        actions =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, actions}

      other ->
        other
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
