defmodule Mix.Tasks.HydraX.Conversations do
  use Mix.Task

  @shortdoc "Lists conversations, sends messages, or retries failed Telegram deliveries"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["start", message | rest] ->
        start_conversation(message, rest)

      ["send", id, message | _rest] ->
        send_message(id, message)

      ["archive", id] ->
        archive_conversation(id)

      ["export", id] ->
        export_conversation(id)

      ["retry-delivery", id] ->
        retry_delivery(id)

      _ ->
        list_conversations(args)
    end
  end

  defp retry_delivery(id) do
    conversation = HydraX.Runtime.get_conversation!(String.to_integer(id))

    case HydraX.Gateway.retry_conversation_delivery(conversation) do
      {:ok, updated} ->
        Mix.shell().info(
          "Retried #{updated.metadata["last_delivery"]["channel"]} delivery for conversation #{updated.id}"
        )

      {:error, reason} ->
        Mix.raise("retry failed: #{inspect(reason)}")
    end
  end

  defp start_conversation(message, rest) do
    {opts, _args, _invalid} =
      OptionParser.parse(rest, strict: [agent: :string, channel: :string, title: :string])

    agent =
      case opts[:agent] do
        nil -> HydraX.Runtime.ensure_default_agent!()
        slug -> HydraX.Runtime.get_agent_by_slug(slug) || raise "unknown agent #{slug}"
      end

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, conversation} =
      HydraX.Runtime.start_conversation(agent, %{
        channel: opts[:channel] || "control_plane",
        title: opts[:title] || "Control plane · #{Date.utc_today()}",
        metadata: %{"source" => "mix hydra_x.conversations"}
      })

    response =
      HydraX.Agent.Channel.submit(agent, conversation, message, %{"source" => "control_plane"})

    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info(response)
  end

  defp send_message(id, message) do
    conversation = HydraX.Runtime.get_conversation!(String.to_integer(id))
    agent = conversation.agent || HydraX.Runtime.get_agent!(conversation.agent_id)

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    response =
      HydraX.Agent.Channel.submit(agent, conversation, message, %{"source" => "control_plane"})

    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info(response)
  end

  defp archive_conversation(id) do
    conversation = HydraX.Runtime.archive_conversation!(String.to_integer(id))
    Mix.shell().info("conversation=#{conversation.id}")
    Mix.shell().info("status=#{conversation.status}")
  end

  defp export_conversation(id) do
    export = HydraX.Runtime.export_conversation_transcript!(String.to_integer(id))
    Mix.shell().info("conversation=#{export.conversation.id}")
    Mix.shell().info("path=#{export.path}")
  end

  defp list_conversations(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [status: :string, channel: :string, search: :string, limit: :integer]
      )

    HydraX.Runtime.list_conversations(
      limit: opts[:limit] || 25,
      status: opts[:status],
      channel: opts[:channel],
      search: opts[:search]
    )
    |> Enum.each(fn conversation ->
      delivery =
        case conversation.metadata do
          %{"last_delivery" => %{"status" => status, "channel" => channel}} ->
            "#{channel}:#{status}"

          _ ->
            "-"
        end

      Mix.shell().info(
        Enum.join(
          [
            to_string(conversation.id),
            conversation.status,
            conversation.channel,
            conversation.title || "Untitled",
            delivery
          ],
          "\t"
        )
      )
    end)
  end
end
