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

    HydraX.Runtime.health_snapshot(filters)
    |> Enum.each(fn check ->
      Mix.shell().info(
        "[#{String.upcase(Atom.to_string(check.status))}] #{check.name}: #{check.detail}"
      )
    end)
  end
end
