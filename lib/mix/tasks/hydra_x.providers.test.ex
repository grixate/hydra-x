defmodule Mix.Tasks.HydraX.Providers.Test do
  use Mix.Task

  @shortdoc "Tests the enabled provider or a specific provider id"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [id: :integer])

    provider =
      case opts[:id] do
        nil -> HydraX.Runtime.enabled_provider()
        id -> HydraX.Runtime.get_provider_config!(id)
      end

    if provider do
      case HydraX.Runtime.test_provider_config(provider) do
        {:ok, result} ->
          Mix.shell().info("provider=#{provider.name}")
          Mix.shell().info("reply=#{result.content}")

        {:error, reason} ->
          Mix.raise("provider test failed: #{inspect(reason)}")
      end
    else
      Mix.shell().info("No enabled provider configured.")
    end
  end
end
