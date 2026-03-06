defmodule Mix.Tasks.HydraX.Jobs do
  use Mix.Task

  @shortdoc "Lists scheduled jobs or runs a specific job"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()

    {opts, positional, _invalid} =
      OptionParser.parse(args, strict: [run: :integer], aliases: [r: :run])

    case opts[:run] || parse_positional_run(positional) do
      nil -> list_jobs()
      id -> run_job(id)
    end
  end

  defp list_jobs do
    HydraX.Runtime.list_scheduled_jobs(limit: 100)
    |> Enum.each(fn job ->
      Mix.shell().info(
        "#{job.id}\t#{job.name}\t#{job.kind}\t#{if(job.enabled, do: "enabled", else: "paused")}\tnext=#{format_datetime(job.next_run_at)}"
      )
    end)
  end

  defp run_job(id) do
    job = HydraX.Runtime.get_scheduled_job!(id)

    case HydraX.Runtime.run_scheduled_job(job) do
      {:ok, run} ->
        Mix.shell().info("job=#{job.name}")
        Mix.shell().info("status=#{run.status}")
        Mix.shell().info("output=#{run.output}")

      {:error, reason} ->
        Mix.raise("job execution failed: #{inspect(reason)}")
    end
  end

  defp parse_positional_run(["run", id]), do: String.to_integer(id)
  defp parse_positional_run(_args), do: nil

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
