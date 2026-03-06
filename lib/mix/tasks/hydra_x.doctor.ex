defmodule Mix.Tasks.HydraX.Doctor do
  use Mix.Task

  @shortdoc "Prints a preview-readiness report for Hydra-X"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()

    report = HydraX.Runtime.readiness_report()

    Mix.shell().info("readiness=#{String.upcase(Atom.to_string(report.summary))}")

    Enum.each(report.items, fn item ->
      required = if item.required, do: "required", else: "recommended"

      Mix.shell().info(
        "[#{String.upcase(Atom.to_string(item.status))}] #{item.label} (#{required}): #{item.detail}"
      )
    end)
  end
end
