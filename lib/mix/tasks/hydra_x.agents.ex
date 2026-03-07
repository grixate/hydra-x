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

      _ ->
        HydraX.Runtime.list_agents()
        |> Enum.each(fn agent ->
          Mix.shell().info(
            Enum.join(
              [
                to_string(agent.id),
                agent.slug,
                agent.status,
                if(HydraX.Agent.running?(agent), do: "runtime:up", else: "runtime:down"),
                if(agent.is_default, do: "default", else: "-"),
                agent.workspace_root
              ],
              "\t"
            )
          )
        end)
    end
  end
end
