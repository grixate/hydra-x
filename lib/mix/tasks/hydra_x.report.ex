defmodule Mix.Tasks.HydraX.Report do
  use Mix.Task

  @shortdoc "Exports an operator-facing runtime report in markdown and JSON"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()
    HydraX.Runtime.ensure_default_jobs!()

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          only_warn: :boolean,
          required_only: :boolean,
          search: :string,
          safety_limit: :integer,
          job_limit: :integer,
          conversation_limit: :integer
        ],
        aliases: [o: :output]
      )

    output_root = opts[:output] || Path.join(HydraX.Config.install_root(), "reports")

    {:ok, export} =
      HydraX.Report.export_snapshot(output_root,
        only_warn: opts[:only_warn] || false,
        required_only: opts[:required_only] || false,
        search: opts[:search],
        safety_limit: opts[:safety_limit] || 20,
        job_limit: opts[:job_limit] || 10,
        conversation_limit: opts[:conversation_limit] || 10
      )

    Mix.shell().info("markdown=#{export.markdown_path}")
    Mix.shell().info("json=#{export.json_path}")

    Mix.shell().info(
      "readiness=#{String.upcase(Atom.to_string(export.snapshot.readiness.summary))}"
    )
  end
end
