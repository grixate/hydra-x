defmodule Mix.Tasks.HydraX.Providers do
  use Mix.Task

  @shortdoc "Lists providers and manages active provider lifecycle"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["activate", id] ->
        provider = HydraX.Runtime.activate_provider!(String.to_integer(id))
        Mix.shell().info("active=#{provider.name}")

      ["toggle", id] ->
        provider = HydraX.Runtime.toggle_provider_enabled!(String.to_integer(id))
        Mix.shell().info("provider=#{provider.name}")
        Mix.shell().info("enabled=#{provider.enabled}")

      ["delete", id] ->
        provider = HydraX.Runtime.get_provider_config!(String.to_integer(id))
        HydraX.Runtime.delete_provider_config!(provider.id)
        Mix.shell().info("deleted=#{provider.name}")

      _ ->
        HydraX.Runtime.list_provider_configs()
        |> Enum.each(fn provider ->
          Mix.shell().info(
            Enum.join(
              [
                to_string(provider.id),
                provider.name,
                provider.kind,
                provider.model,
                if(provider.enabled, do: "active", else: "standby")
              ],
              "\t"
            )
          )
        end)
    end
  end
end
