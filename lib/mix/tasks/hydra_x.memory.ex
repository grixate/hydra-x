defmodule Mix.Tasks.HydraX.Memory do
  use Mix.Task

  @shortdoc "Lists, creates, updates, links, and syncs typed memory"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["create", type, content | rest] ->
        create_memory(type, content, rest)

      ["update", id, content | rest] ->
        update_memory(id, content, rest)

      ["link", from_id, to_id, kind | rest] ->
        link_memories(from_id, to_id, kind, rest)

      ["sync" | rest] ->
        sync_memory(rest)

      _ ->
        list_memories(args)
    end
  end

  defp create_memory(type, content, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest, strict: [agent: :string, importance: :float])

    agent = resolve_agent(opts[:agent])

    {:ok, memory} =
      HydraX.Memory.create_memory(%{
        agent_id: agent.id,
        type: type,
        content: content,
        importance: opts[:importance] || 0.7,
        last_seen_at: DateTime.utc_now()
      })

    Mix.shell().info("memory=#{memory.id}")
  end

  defp update_memory(id, content, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest, strict: [importance: :float, type: :string])

    memory = HydraX.Memory.get_memory!(String.to_integer(id))

    {:ok, memory} =
      HydraX.Memory.update_memory(memory, %{
        content: content,
        importance: opts[:importance] || memory.importance,
        type: opts[:type] || memory.type,
        last_seen_at: DateTime.utc_now()
      })

    Mix.shell().info("memory=#{memory.id}")
  end

  defp link_memories(from_id, to_id, kind, rest) do
    {opts, _args, _invalid} = OptionParser.parse(rest, strict: [weight: :float])

    {:ok, edge} =
      HydraX.Memory.link_memories(%{
        from_memory_id: String.to_integer(from_id),
        to_memory_id: String.to_integer(to_id),
        kind: kind,
        weight: opts[:weight] || 1.0
      })

    Mix.shell().info("edge=#{edge.id}")
  end

  defp sync_memory(rest) do
    {opts, _args, _invalid} = OptionParser.parse(rest, strict: [agent: :string])
    agent = resolve_agent(opts[:agent])
    {:ok, path} = HydraX.Memory.sync_markdown(agent)
    Mix.shell().info("path=#{path}")
  end

  defp list_memories(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          agent: :string,
          type: :string,
          search: :string,
          min_importance: :float,
          limit: :integer
        ]
      )

    agent_id =
      case opts[:agent] do
        nil -> nil
        slug -> resolve_agent(slug).id
      end

    memories =
      case opts[:search] do
        nil ->
          HydraX.Memory.list_memories(
            limit: opts[:limit] || 50,
            agent_id: agent_id,
            type: opts[:type],
            min_importance: opts[:min_importance]
          )

        query ->
          HydraX.Memory.search(
            agent_id,
            query,
            opts[:limit] || 50,
            type: opts[:type],
            min_importance: opts[:min_importance]
          )
      end

    memories
    |> Enum.each(fn memory ->
      Mix.shell().info(
        Enum.join(
          [
            to_string(memory.id),
            to_string(memory.agent_id),
            memory.type,
            Float.to_string(memory.importance),
            memory.content
          ],
          "\t"
        )
      )
    end)
  end

  defp resolve_agent(nil), do: HydraX.Runtime.ensure_default_agent!()

  defp resolve_agent(slug) do
    HydraX.Runtime.get_agent_by_slug(slug) || raise "unknown agent #{slug}"
  end
end
