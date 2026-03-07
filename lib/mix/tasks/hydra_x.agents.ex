defmodule Mix.Tasks.HydraX.Agents do
  use Mix.Task

  @shortdoc "Lists agents and manages default/workspace lifecycle"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
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
