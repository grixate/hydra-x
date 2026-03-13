defmodule Mix.Tasks.HydraX.Mcp do
  use Mix.Task

  @shortdoc "Manage persisted MCP server configs"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["actions", agent_ref | rest] ->
        list_actions(agent_ref, rest)

      ["invoke", agent_ref, action | rest] ->
        invoke_binding(agent_ref, action, rest)

      ["bindings", agent_ref] ->
        list_bindings(agent_ref)

      ["refresh-bindings", agent_ref] ->
        refresh_bindings(agent_ref)

      ["enable-binding", id] ->
        binding = HydraX.Runtime.enable_agent_mcp_server!(String.to_integer(id))
        Mix.shell().info("binding=#{binding.id}")
        Mix.shell().info("status=enabled")

      ["disable-binding", id] ->
        binding = HydraX.Runtime.disable_agent_mcp_server!(String.to_integer(id))
        Mix.shell().info("binding=#{binding.id}")
        Mix.shell().info("status=disabled")

      ["test-all"] ->
        test_all_servers()

      ["test", id] ->
        config = HydraX.Runtime.get_mcp_server!(String.to_integer(id))
        print_test_result(HydraX.Runtime.test_mcp_server(config))

      ["delete", id] ->
        config = HydraX.Runtime.delete_mcp_server!(String.to_integer(id))
        Mix.shell().info("deleted=#{config.name}")

      ["save" | rest] ->
        save_server(rest)

      _ ->
        list_servers()
    end
  end

  defp invoke_binding(agent_ref, action, args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [server: :string, json: :string, param: :keep]
      )

    agent = resolve_agent(agent_ref)
    params = build_invoke_params(opts)

    {:ok, result} =
      HydraX.Runtime.invoke_agent_mcp(agent.id, action, params, server: opts[:server])

    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("action=#{action}")
    Mix.shell().info("count=#{result.count}")

    Enum.each(result.results, fn entry ->
      line =
        [
          entry.name,
          entry.transport,
          entry.status,
          Map.get(entry, :detail) || format_invoke_result(Map.get(entry, :result))
        ]
        |> Enum.join("\t")

      Mix.shell().info(line)
    end)
  end

  defp list_actions(agent_ref, args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [server: :string]
      )

    agent = resolve_agent(agent_ref)

    {:ok, result} =
      HydraX.Runtime.list_agent_mcp_actions(agent.id,
        server: opts[:server],
        refresh: true
      )

    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("count=#{result.count}")

    Enum.each(result.results, fn entry ->
      detail =
        case entry do
          %{actions: actions, catalog_source: source} when is_list(actions) and actions != [] ->
            "#{Enum.join(actions, ", ")} [#{source}]"

          %{actions: []} ->
            "no actions"

          %{detail: detail} ->
            detail
        end

      Mix.shell().info(
        Enum.join(
          [entry.name, entry.transport, entry.status, detail],
          "\t"
        )
      )
    end)
  end

  defp save_server(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          id: :integer,
          name: :string,
          transport: :string,
          command: :string,
          args: :string,
          cwd: :string,
          url: :string,
          healthcheck_path: :string,
          auth_token: :string,
          retry_limit: :integer,
          enabled: :string
        ]
      )

    config =
      case opts[:id] do
        nil -> %HydraX.Runtime.MCPServerConfig{}
        id -> HydraX.Runtime.get_mcp_server!(id)
      end

    {:ok, saved} =
      HydraX.Runtime.save_mcp_server(config, %{
        "name" => opts[:name],
        "transport" => opts[:transport],
        "command" => opts[:command],
        "args_csv" => opts[:args],
        "cwd" => opts[:cwd],
        "url" => opts[:url],
        "healthcheck_path" => opts[:healthcheck_path],
        "auth_token" => opts[:auth_token],
        "retry_limit" => opts[:retry_limit],
        "enabled" => parse_boolean(opts[:enabled], true)
      })

    Mix.shell().info("saved=#{saved.id}")
    list_servers()
  end

  defp list_servers do
    HydraX.Runtime.list_mcp_servers()
    |> Enum.each(fn server ->
      Mix.shell().info(
        Enum.join(
          [
            to_string(server.id),
            server.name,
            server.transport,
            if(server.enabled, do: "enabled", else: "disabled"),
            server.command || server.url || "-"
          ],
          "\t"
        )
      )
    end)
  end

  defp list_bindings(agent_ref) do
    agent = resolve_agent(agent_ref)
    agent_status = HydraX.Runtime.agent_mcp_statuses(agent.id)

    HydraX.Runtime.list_agent_mcp_servers(agent.id)
    |> Enum.each(fn binding ->
      status = Enum.find(agent_status.bindings, &(&1.id == binding.id))

      Mix.shell().info(
        Enum.join(
          [
            to_string(binding.id),
            binding.mcp_server_config.name,
            binding.mcp_server_config.transport,
            if(binding.enabled, do: "enabled", else: "disabled"),
            to_string((status && status.status) || :unknown)
          ],
          "\t"
        )
      )
    end)
  end

  defp refresh_bindings(agent_ref) do
    agent = resolve_agent(agent_ref)
    {:ok, bindings} = HydraX.Runtime.refresh_agent_mcp_servers(agent.id)
    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("refreshed=#{length(bindings)}")
    list_bindings(agent_ref)
  end

  defp test_all_servers do
    HydraX.Runtime.list_mcp_servers()
    |> Enum.each(fn server ->
      Mix.shell().info("server=#{server.name}")
      print_test_result(HydraX.Runtime.test_mcp_server(server))
    end)
  end

  defp print_test_result({:ok, result}) do
    Mix.shell().info("status=ok")
    Mix.shell().info("detail=#{result.detail}")
  end

  defp print_test_result({:error, reason}) do
    Mix.shell().info("status=error")
    Mix.shell().info("detail=#{inspect(reason)}")
  end

  defp build_invoke_params(opts) do
    json_params =
      opts
      |> Keyword.get(:json)
      |> decode_json_params()

    param_pairs =
      opts
      |> Keyword.get_values(:param)
      |> Enum.reduce(%{}, fn pair, acc ->
        case String.split(pair, "=", parts: 2) do
          [key, value] when key != "" -> Map.put(acc, key, parse_param_value(value))
          _ -> acc
        end
      end)

    Map.merge(json_params, param_pairs)
  end

  defp decode_json_params(nil), do: %{}
  defp decode_json_params(""), do: %{}

  defp decode_json_params(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      {:ok, _decoded} -> Mix.raise("--json must decode to an object")
      {:error, error} -> Mix.raise("invalid --json payload: #{Exception.message(error)}")
    end
  end

  defp parse_param_value("true"), do: true
  defp parse_param_value("false"), do: false
  defp parse_param_value("null"), do: nil

  defp parse_param_value(value) do
    cond do
      match?({_, ""}, Integer.parse(value)) ->
        {parsed, ""} = Integer.parse(value)
        parsed

      match?({_, ""}, Float.parse(value)) ->
        {parsed, ""} = Float.parse(value)
        parsed

      true ->
        value
    end
  end

  defp format_invoke_result(nil), do: "-"

  defp format_invoke_result(%{status: status, url: url}) do
    "HTTP #{status} #{url}"
  end

  defp format_invoke_result(%{status: status, command: command}) when is_binary(command) do
    "STDIO #{status} #{command}"
  end

  defp format_invoke_result(result) when is_map(result) do
    inspect(result, limit: 5, printable_limit: 120)
  end

  defp format_invoke_result(result) do
    inspect(result, printable_limit: 120)
  end

  defp parse_boolean(nil, default), do: default
  defp parse_boolean("true", _default), do: true
  defp parse_boolean("false", _default), do: false
  defp parse_boolean(_value, default), do: default

  defp resolve_agent(value) do
    case Integer.parse(value) do
      {id, ""} ->
        HydraX.Runtime.get_agent!(id)

      _ ->
        HydraX.Runtime.get_agent_by_slug(value) || raise "unknown agent #{value}"
    end
  end
end
