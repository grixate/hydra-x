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

      ["delete", id] ->
        delete_memory(id)

      ["merge", source_id, target_id | rest] ->
        merge_memory(source_id, target_id, rest)

      ["supersede", source_id, target_id] ->
        supersede_memory(source_id, target_id)

      ["conflict", source_id, target_id | rest] ->
        conflict_memory(source_id, target_id, rest)

      ["resolve", winner_id, loser_id | rest] ->
        resolve_conflict(winner_id, loser_id, rest)

      ["link", from_id, to_id, kind | rest] ->
        link_memories(from_id, to_id, kind, rest)

      ["unlink", id] ->
        unlink_memory(id)

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

  defp delete_memory(id) do
    memory = HydraX.Memory.delete_memory!(String.to_integer(id))
    Mix.shell().info("deleted_memory=#{memory.id}")
  end

  defp merge_memory(source_id, target_id, rest) do
    {opts, _args, _invalid} = OptionParser.parse(rest, strict: [content: :string])

    {:ok, result} =
      HydraX.Memory.reconcile_memory!(
        String.to_integer(source_id),
        String.to_integer(target_id),
        :merge,
        content: opts[:content]
      )

    Mix.shell().info("merged=#{result.source.id}->#{result.target.id}")
    Mix.shell().info("edge=#{result.edge.id}")
  end

  defp supersede_memory(source_id, target_id) do
    {:ok, result} =
      HydraX.Memory.reconcile_memory!(
        String.to_integer(source_id),
        String.to_integer(target_id),
        :supersede
      )

    Mix.shell().info("superseded=#{result.source.id}->#{result.target.id}")
    Mix.shell().info("edge=#{result.edge.id}")
  end

  defp conflict_memory(source_id, target_id, rest) do
    {opts, _args, _invalid} = OptionParser.parse(rest, strict: [reason: :string])

    {:ok, result} =
      HydraX.Memory.conflict_memory!(
        String.to_integer(source_id),
        String.to_integer(target_id),
        reason: opts[:reason]
      )

    Mix.shell().info("conflicted=#{result.source.id}<->#{result.target.id}")
    Mix.shell().info("edge=#{result.edge.id}")
  end

  defp resolve_conflict(winner_id, loser_id, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest, strict: [content: :string, note: :string, loser_status: :string])

    {:ok, result} =
      HydraX.Memory.resolve_conflict!(
        String.to_integer(winner_id),
        String.to_integer(loser_id),
        content: opts[:content],
        note: opts[:note],
        loser_status: opts[:loser_status] || "superseded"
      )

    Mix.shell().info("resolved=#{result.winner.id}>#{result.loser.id}")
    Mix.shell().info("edge=#{result.edge.id}")
  end

  defp unlink_memory(id) do
    edge = HydraX.Memory.delete_edge!(String.to_integer(id))
    Mix.shell().info("deleted_edge=#{edge.id}")
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
          status: :string,
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
            status: opts[:status] || "active",
            min_importance: opts[:min_importance]
          )
          |> Enum.map(&%{entry: &1, score: nil, reasons: []})

        query ->
          HydraX.Memory.search_ranked(
            agent_id,
            query,
            opts[:limit] || 50,
            type: opts[:type],
            status: opts[:status] || "active",
            min_importance: opts[:min_importance]
          )
      end

    memories
    |> Enum.each(fn ranked ->
      memory = ranked.entry

      Mix.shell().info(
        Enum.join(
          [
            to_string(memory.id),
            to_string(memory.agent_id),
            memory.type,
            memory.status,
            Float.to_string(memory.importance),
            if(is_float(ranked.score), do: Float.to_string(ranked.score), else: "-"),
            if(is_float(ranked[:vector_score]),
              do: Float.to_string(ranked.vector_score),
              else: "-"
            ),
            get_in(memory.metadata || %{}, ["embedding_backend"]) || "-",
            Enum.join(ranked.reasons || [], ", "),
            get_in(memory.metadata || %{}, ["source_file"]) || "-",
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
