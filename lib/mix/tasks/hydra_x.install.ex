defmodule Mix.Tasks.HydraX.Install do
  use Mix.Task

  @shortdoc "Exports a deployment-ready env template and readiness note"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [output: :string], aliases: [o: :output])

    output_root = opts[:output] || HydraX.Config.install_root()

    {:ok, export} = HydraX.Install.export_snapshot(output_root)

    Mix.shell().info("env=#{export.env_path}")
    Mix.shell().info("note=#{export.note_path}")

    Mix.shell().info(
      "readiness=#{String.upcase(Atom.to_string(export.snapshot.readiness.summary))}"
    )
  end
end
