defmodule Mix.Tasks.HydraX.Chat do
  use Mix.Task

  @shortdoc "Runs a one-shot Hydra-X conversation"

  @impl true
  def run(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [message: :string, agent: :string, channel: :string],
        aliases: [m: :message]
      )

    message = opts[:message] || raise "pass a message with -m or --message"
    Mix.Task.run("app.start")

    agent =
      case opts[:agent] do
        nil -> HydraX.Runtime.ensure_default_agent!()
        slug -> HydraX.Runtime.get_agent_by_slug(slug) || raise "unknown agent #{slug}"
      end

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, conversation} =
      HydraX.Runtime.start_conversation(agent, %{
        channel: opts[:channel] || "cli",
        title: "CLI · #{Date.utc_today()}",
        metadata: %{source: "mix hydra_x.chat"}
      })

    response = HydraX.Agent.Channel.submit(agent, conversation, message, %{source: "cli"})
    HydraX.Memory.sync_markdown(agent)
    Mix.shell().info(render_channel_response(response))
  end

  defp render_channel_response({:deferred, message}), do: message
  defp render_channel_response(message), do: message
end
