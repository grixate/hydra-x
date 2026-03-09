defmodule Mix.Tasks.HydraX.Agents do
  use Mix.Task

  @shortdoc "Lists agents and manages default/workspace lifecycle"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["start", id] ->
        agent = HydraX.Runtime.start_agent_runtime!(String.to_integer(id))
        Mix.shell().info("runtime=#{agent.slug}:up")

      ["stop", id] ->
        agent = HydraX.Runtime.stop_agent_runtime!(String.to_integer(id))
        Mix.shell().info("runtime=#{agent.slug}:down")

      ["restart", id] ->
        agent = HydraX.Runtime.restart_agent_runtime!(String.to_integer(id))
        Mix.shell().info("runtime=#{agent.slug}:restarted")

      ["reconcile"] ->
        summary = HydraX.Runtime.reconcile_agents!()
        Mix.shell().info("started=#{summary.started}")
        Mix.shell().info("stopped=#{summary.stopped}")

      ["default", id] ->
        agent = HydraX.Runtime.set_default_agent!(String.to_integer(id))
        Mix.shell().info("default=#{agent.slug}")

      ["toggle", id] ->
        agent = HydraX.Runtime.toggle_agent_status!(String.to_integer(id))
        Mix.shell().info("status=#{agent.slug}:#{agent.status}")

      ["repair", id] ->
        agent = HydraX.Runtime.repair_agent_workspace!(String.to_integer(id))
        Mix.shell().info("workspace=#{agent.workspace_root}")

      ["bulletin", id] ->
        bulletin = HydraX.Runtime.refresh_agent_bulletin!(String.to_integer(id))
        Mix.shell().info("agent=#{bulletin.agent.slug}")
        Mix.shell().info("memory_count=#{bulletin.memory_count}")
        Mix.shell().info(bulletin.content || "No bulletin yet")

      ["compaction", id | rest] ->
        manage_compaction_policy(id, rest)

      ["tool-policy", id | rest] ->
        manage_tool_policy(id, rest)

      ["provider-routing", id | rest] ->
        manage_provider_routing(id, rest)

      ["warmup", id] ->
        warm_agent_route(id)

      _ ->
        HydraX.Runtime.list_agents()
        |> Enum.each(fn agent ->
          runtime = HydraX.Runtime.agent_runtime_status(agent)

          Mix.shell().info(
            Enum.join(
              [
                to_string(agent.id),
                agent.slug,
                agent.status,
                if(HydraX.Agent.running?(agent), do: "runtime:up", else: "runtime:down"),
                "readiness:#{runtime.readiness}",
                if(agent.is_default, do: "default", else: "-"),
                agent.workspace_root
              ],
              "\t"
            )
          )
        end)
    end
  end

  defp manage_compaction_policy(id, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest, strict: [soft: :integer, medium: :integer, hard: :integer])

    agent_id = String.to_integer(id)

    policy =
      if Enum.any?([opts[:soft], opts[:medium], opts[:hard]], &(!is_nil(&1))) do
        HydraX.Runtime.save_compaction_policy!(agent_id, %{
          "soft" => opts[:soft],
          "medium" => opts[:medium],
          "hard" => opts[:hard]
        })
      else
        HydraX.Runtime.compaction_policy(agent_id)
      end

    agent = HydraX.Runtime.get_agent!(agent_id)
    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("soft=#{policy.soft}")
    Mix.shell().info("medium=#{policy.medium}")
    Mix.shell().info("hard=#{policy.hard}")
  end

  defp manage_tool_policy(id, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest,
        strict: [
          reset: :boolean,
          workspace_list: :string,
          workspace_read: :string,
          workspace_write: :string,
          http_fetch: :string,
          web_search: :string,
          shell: :string,
          shell_allowlist: :string,
          http_allowlist: :string,
          workspace_write_channels: :string,
          http_fetch_channels: :string,
          web_search_channels: :string,
          shell_channels: :string
        ]
      )

    agent_id = String.to_integer(id)

    cond do
      opts[:reset] ->
        HydraX.Runtime.delete_agent_tool_policy!(agent_id)
        Mix.shell().info("agent=#{HydraX.Runtime.get_agent!(agent_id).slug}")
        Mix.shell().info("tool_policy=reset")

      Enum.any?(opts, fn {key, _value} -> key != :reset end) ->
        attrs =
          %{}
          |> maybe_put_boolean("workspace_list_enabled", opts[:workspace_list])
          |> maybe_put_boolean("workspace_read_enabled", opts[:workspace_read])
          |> maybe_put_boolean("workspace_write_enabled", opts[:workspace_write])
          |> maybe_put_boolean("http_fetch_enabled", opts[:http_fetch])
          |> maybe_put_boolean("web_search_enabled", opts[:web_search])
          |> maybe_put_boolean("shell_command_enabled", opts[:shell])
          |> maybe_put("shell_allowlist_csv", opts[:shell_allowlist])
          |> maybe_put("http_allowlist_csv", opts[:http_allowlist])
          |> maybe_put("workspace_write_channels_csv", opts[:workspace_write_channels])
          |> maybe_put("http_fetch_channels_csv", opts[:http_fetch_channels])
          |> maybe_put("web_search_channels_csv", opts[:web_search_channels])
          |> maybe_put("shell_command_channels_csv", opts[:shell_channels])

        {:ok, _policy} = HydraX.Runtime.save_agent_tool_policy(agent_id, attrs)
        print_tool_policy(agent_id)

      true ->
        print_tool_policy(agent_id)
    end
  end

  defp print_tool_policy(agent_id) do
    agent = HydraX.Runtime.get_agent!(agent_id)
    policy = HydraX.Runtime.effective_tool_policy(agent_id)

    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("workspace_list=#{policy.workspace_list_enabled}")
    Mix.shell().info("workspace_read=#{policy.workspace_read_enabled}")
    Mix.shell().info("workspace_write=#{policy.workspace_write_enabled}")
    Mix.shell().info("web_search=#{policy.web_search_enabled}")
    Mix.shell().info("http_fetch=#{policy.http_fetch_enabled}")
    Mix.shell().info("shell=#{policy.shell_command_enabled}")
    Mix.shell().info("workspace_write_channels=#{Enum.join(policy.workspace_write_channels, ",")}")
    Mix.shell().info("http_fetch_channels=#{Enum.join(policy.http_fetch_channels, ",")}")
    Mix.shell().info("web_search_channels=#{Enum.join(policy.web_search_channels, ",")}")
    Mix.shell().info("shell_channels=#{Enum.join(policy.shell_command_channels, ",")}")
    Mix.shell().info("shell_allowlist=#{Enum.join(policy.shell_allowlist, ",")}")
    Mix.shell().info("http_allowlist=#{Enum.join(policy.http_allowlist, ",")}")
  end

  defp manage_provider_routing(id, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest,
        strict: [
          reset: :boolean,
          default_provider: :integer,
          channel_provider: :integer,
          scheduler_provider: :integer,
          cortex_provider: :integer,
          compactor_provider: :integer,
          fallbacks: :string
        ]
      )

    agent_id = String.to_integer(id)

    cond do
      opts[:reset] ->
        HydraX.Runtime.clear_agent_provider_routing!(agent_id)
        print_provider_routing(agent_id)

      Enum.any?(opts, fn {key, _value} -> key != :reset end) ->
        attrs =
          %{}
          |> maybe_put("default_provider_id", opts[:default_provider])
          |> maybe_put("channel_provider_id", opts[:channel_provider])
          |> maybe_put("scheduler_provider_id", opts[:scheduler_provider])
          |> maybe_put("cortex_provider_id", opts[:cortex_provider])
          |> maybe_put("compactor_provider_id", opts[:compactor_provider])
          |> maybe_put("fallback_provider_ids_csv", opts[:fallbacks])

        {:ok, _agent} = HydraX.Runtime.save_agent_provider_routing(agent_id, attrs)
        print_provider_routing(agent_id)

      true ->
        print_provider_routing(agent_id)
    end
  end

  defp warm_agent_route(id) do
    agent_id = String.to_integer(id)
    {:ok, agent, status} = HydraX.Runtime.warm_agent_provider_routing(agent_id)
    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("warmup=#{status["status"]}")

    if status["selected_provider_name"],
      do: Mix.shell().info("selected=#{status["selected_provider_name"]}")

    if status["last_error"], do: Mix.shell().info("error=#{status["last_error"]}")
  end

  defp print_provider_routing(agent_id) do
    agent = HydraX.Runtime.get_agent!(agent_id)
    profile = HydraX.Runtime.provider_routing_profile(agent_id)
    route = HydraX.Runtime.effective_provider_route(agent_id, "channel")

    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("default_provider_id=#{profile["default_provider_id"] || ""}")

    Mix.shell().info(
      "channel_provider_id=#{get_in(profile, ["process_overrides", "channel"]) || ""}"
    )

    Mix.shell().info(
      "scheduler_provider_id=#{get_in(profile, ["process_overrides", "scheduler"]) || ""}"
    )

    Mix.shell().info(
      "cortex_provider_id=#{get_in(profile, ["process_overrides", "cortex"]) || ""}"
    )

    Mix.shell().info(
      "compactor_provider_id=#{get_in(profile, ["process_overrides", "compactor"]) || ""}"
    )

    Mix.shell().info(
      "fallback_provider_ids=#{Enum.join(profile["fallback_provider_ids"] || [], ",")}"
    )

    Mix.shell().info(
      "effective=#{(route.provider && (route.provider.name || route.provider.model)) || "mock"}"
    )

    Mix.shell().info("source=#{route.source}")
    Mix.shell().info("warmup=#{route.warmup["status"]}")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_boolean(map, _key, nil), do: map
  defp maybe_put_boolean(map, key, value), do: Map.put(map, key, parse_bool!(value))

  defp parse_bool!("true"), do: true
  defp parse_bool!("false"), do: false
  defp parse_bool!(value), do: raise("expected true/false, got #{inspect(value)}")
end
