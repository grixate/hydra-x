defmodule Mix.Tasks.HydraX.Healthcheck do
  use Mix.Task

  @shortdoc "Prints a Hydra-X runtime health snapshot"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()
    HydraX.Runtime.ensure_default_jobs!()

    HydraX.Runtime.health_snapshot()
    |> Enum.each(fn check ->
      Mix.shell().info(
        "[#{String.upcase(Atom.to_string(check.status))}] #{check.name}: #{check.detail}"
      )
    end)
  end
end
