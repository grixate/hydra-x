defmodule Mix.Tasks.HydraX.Healthcheck do
  use Mix.Task

  @shortdoc "Prints a Hydra-X runtime health snapshot"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()
    HydraX.Runtime.ensure_default_jobs!()

    {opts, _positional, _invalid} =
      OptionParser.parse(args, strict: [only_warn: :boolean, search: :string])

    filters = [
      status: if(opts[:only_warn], do: :warn, else: nil),
      search: opts[:search]
    ]

    checks = HydraX.Runtime.health_snapshot(filters)

    Mix.shell().info("checks=#{length(checks)}")
    Mix.shell().info("warn=#{Enum.count(checks, &(&1.status == :warn))}")
    Mix.shell().info("ok=#{Enum.count(checks, &(&1.status == :ok))}")

    Enum.each(checks, fn check ->
      Mix.shell().info(
        "[#{String.upcase(Atom.to_string(check.status))}] #{check.name}: #{check.detail}"
      )
    end)
  end
end
