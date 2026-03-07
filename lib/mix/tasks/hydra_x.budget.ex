defmodule Mix.Tasks.HydraX.Budget do
  use Mix.Task

  @shortdoc "Inspects and updates budget policy for an agent"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          agent: :string,
          daily_limit: :integer,
          conversation_limit: :integer,
          soft_warning_at: :float,
          hard_limit_action: :string,
          enabled: :string
        ]
      )

    agent = resolve_agent(opts[:agent])
    policy = HydraX.Budget.ensure_policy!(agent.id)

    if update_requested?(opts) do
      attrs =
        %{}
        |> maybe_put(:daily_limit, opts[:daily_limit])
        |> maybe_put(:conversation_limit, opts[:conversation_limit])
        |> maybe_put(:soft_warning_at, opts[:soft_warning_at])
        |> maybe_put(:hard_limit_action, opts[:hard_limit_action])
        |> maybe_put(:enabled, parse_enabled(opts[:enabled]))
        |> Map.put(:agent_id, agent.id)

      {:ok, policy} = HydraX.Budget.save_policy(policy, attrs)
      print_policy(agent, policy)
    else
      print_policy(agent, policy)
    end
  end

  defp resolve_agent(nil), do: HydraX.Runtime.ensure_default_agent!()

  defp resolve_agent(slug) do
    HydraX.Runtime.get_agent_by_slug(slug) || Mix.raise("unknown agent #{slug}")
  end

  defp update_requested?(opts) do
    Enum.any?(
      [:daily_limit, :conversation_limit, :soft_warning_at, :hard_limit_action, :enabled],
      &Keyword.has_key?(opts, &1)
    )
  end

  defp print_policy(agent, policy) do
    usage = HydraX.Budget.usage_snapshot(agent.id, nil)

    Mix.shell().info("agent=#{agent.slug}")
    Mix.shell().info("daily_limit=#{policy.daily_limit}")
    Mix.shell().info("conversation_limit=#{policy.conversation_limit}")
    Mix.shell().info("soft_warning_at=#{policy.soft_warning_at}")
    Mix.shell().info("hard_limit_action=#{policy.hard_limit_action}")
    Mix.shell().info("enabled=#{policy.enabled}")
    Mix.shell().info("daily_tokens=#{usage.daily_tokens}")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_enabled(nil), do: nil
  defp parse_enabled("true"), do: true
  defp parse_enabled("false"), do: false
  defp parse_enabled(value), do: Mix.raise("invalid enabled value #{inspect(value)}")
end
