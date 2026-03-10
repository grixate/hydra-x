defmodule Mix.Tasks.HydraX.Mcp do
  use Mix.Task

  @shortdoc "Manage persisted MCP server configs"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
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
