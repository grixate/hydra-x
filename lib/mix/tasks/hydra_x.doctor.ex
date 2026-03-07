defmodule Mix.Tasks.HydraX.Doctor do
  use Mix.Task

  @shortdoc "Prints a preview-readiness report for Hydra-X"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()
    HydraX.Runtime.ensure_default_jobs!()

    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [required_only: :boolean, only_warn: :boolean, search: :string]
      )

    report =
      HydraX.Runtime.readiness_report(
        required_only: opts[:required_only] || false,
        status: if(opts[:only_warn], do: :warn, else: nil),
        search: opts[:search]
      )

    Mix.shell().info("readiness=#{String.upcase(Atom.to_string(report.summary))}")

    Enum.each(report.items, fn item ->
      required = if item.required, do: "required", else: "recommended"

      Mix.shell().info(
        "[#{String.upcase(Atom.to_string(item.status))}] #{item.label} (#{required}): #{item.detail}"
      )
    end)
  end
end
