defmodule Mix.Tasks.HydraX.Ingest do
  use Mix.Task

  @shortdoc "Lists and manages ingest-backed files"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [agent: :string, force: :boolean, status: :string]
      )

    agent = resolve_agent(opts[:agent])

    case positional do
      ["import", filename] ->
        path = resolve_ingest_path(agent, filename)
        {:ok, result} = HydraX.Runtime.ingest_file(agent.id, path, force: opts[:force] || false)
        Mix.shell().info("file=#{Path.basename(path)}")
        Mix.shell().info("created=#{result.created}")
        Mix.shell().info("skipped=#{result.skipped}")
        Mix.shell().info("archived=#{result.archived}")
        Mix.shell().info("unchanged=#{result.unchanged}")

      ["archive", filename] ->
        {:ok, count} = HydraX.Runtime.archive_file(agent.id, filename)
        Mix.shell().info("file=#{filename}")
        Mix.shell().info("archived=#{count}")

      ["history"] ->
        HydraX.Runtime.list_ingest_runs(agent.id, 20)
        |> maybe_filter_run_status(opts[:status])
        |> Enum.each(fn run ->
          Mix.shell().info(
            "#{run.source_file}\tstatus=#{run.status}\tcreated=#{run.created_count}\tskipped=#{run.skipped_count}\tarchived=#{run.archived_count}\tat=#{format_datetime(run.inserted_at)}"
          )
        end)

      _ ->
        HydraX.Runtime.list_ingested_files(agent.id)
        |> Enum.each(fn file ->
          Mix.shell().info("#{file.file}\tentries=#{file.entries}")
        end)
    end
  end

  defp resolve_agent(nil), do: HydraX.Runtime.ensure_default_agent!()

  defp resolve_agent(slug) do
    HydraX.Runtime.get_agent_by_slug(slug) || raise "unknown agent #{slug}"
  end

  defp resolve_ingest_path(agent, filename) do
    if Path.type(filename) == :absolute do
      filename
    else
      Path.join([agent.workspace_root, "ingest", filename])
    end
  end

  defp maybe_filter_run_status(runs, nil), do: runs
  defp maybe_filter_run_status(runs, ""), do: runs
  defp maybe_filter_run_status(runs, status), do: Enum.filter(runs, &(&1.status == status))

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
