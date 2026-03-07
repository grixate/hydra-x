defmodule Mix.Tasks.HydraX.Jobs do
  use Mix.Task

  @shortdoc "Lists scheduled jobs or runs a specific job"

  @impl true
  def run(args) do
    args = normalize_switches(args)
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()
    HydraX.Runtime.ensure_default_jobs!()

    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          run: :integer,
          kind: :string,
          enabled: :string,
          search: :string,
          limit: :integer,
          name: :string,
          agent: :string,
          prompt: :string,
          schedule_mode: :string,
          interval_minutes: :integer,
          weekday_csv: :string,
          run_hour: :integer,
          run_minute: :integer,
          delivery_enabled: :string,
          delivery_channel: :string,
          delivery_target: :string
        ],
        aliases: [r: :run]
      )

    case opts[:run] || parse_positional_run(positional) do
      nil ->
        case positional do
          ["create"] -> create_job(opts)
          ["update", id] -> update_job(String.to_integer(id), opts)
          ["delete", id] -> delete_job(String.to_integer(id))
          _ -> list_jobs(opts)
        end

      id ->
        run_job(id)
    end
  end

  defp list_jobs(opts) do
    HydraX.Runtime.list_scheduled_jobs(
      limit: opts[:limit] || 100,
      kind: opts[:kind],
      enabled: parse_enabled(opts[:enabled]),
      search: opts[:search]
    )
    |> Enum.each(fn job ->
      Mix.shell().info(
        "#{job.id}\t#{job.name}\t#{job.kind}\t#{schedule_summary(job)}\t#{if(job.enabled, do: "enabled", else: "paused")}\tnext=#{format_datetime(job.next_run_at)}" <>
          if(job.delivery_enabled,
            do: "\tdelivery=#{job.delivery_channel}:#{job.delivery_target}",
            else: ""
          )
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

        if delivery = run.metadata["delivery"],
          do: Mix.shell().info("delivery=#{delivery["status"]}")

      {:error, reason} ->
        Mix.raise("job execution failed: #{inspect(reason)}")
    end
  end

  defp delete_job(id) do
    job = HydraX.Runtime.delete_scheduled_job!(id)
    Mix.shell().info("deleted_job=#{job.id}")
  end

  defp create_job(opts) do
    agent = resolve_agent(opts[:agent])

    attrs =
      opts
      |> build_job_attrs()
      |> Map.put("agent_id", agent.id)

    {:ok, job} = HydraX.Runtime.save_scheduled_job(attrs)
    Mix.shell().info("job=#{job.id}")
    Mix.shell().info("schedule=#{schedule_summary(job)}")
  end

  defp update_job(id, opts) do
    job = HydraX.Runtime.get_scheduled_job!(id)
    attrs = build_job_attrs(opts)

    {:ok, updated} = HydraX.Runtime.save_scheduled_job(job, attrs)
    Mix.shell().info("job=#{updated.id}")
    Mix.shell().info("schedule=#{schedule_summary(updated)}")
  end

  defp build_job_attrs(opts) do
    %{}
    |> maybe_put("name", opts[:name])
    |> maybe_put("kind", opts[:kind])
    |> maybe_put("prompt", opts[:prompt])
    |> maybe_put("schedule_mode", opts[:schedule_mode])
    |> maybe_put("interval_minutes", opts[:interval_minutes])
    |> maybe_put("weekday_csv", opts[:weekday_csv])
    |> maybe_put("run_hour", opts[:run_hour])
    |> maybe_put("run_minute", opts[:run_minute])
    |> maybe_put("enabled", parse_enabled(opts[:enabled]))
    |> maybe_put("delivery_enabled", parse_enabled(opts[:delivery_enabled]))
    |> maybe_put("delivery_channel", opts[:delivery_channel])
    |> maybe_put("delivery_target", opts[:delivery_target])
  end

  defp parse_positional_run(["run", id]), do: String.to_integer(id)
  defp parse_positional_run(_args), do: nil

  defp parse_enabled("true"), do: true
  defp parse_enabled("false"), do: false
  defp parse_enabled(_), do: nil

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp schedule_summary(%{schedule_mode: "daily"} = job) do
    "daily@#{pad(job.run_hour)}:#{pad(job.run_minute)}"
  end

  defp schedule_summary(%{schedule_mode: "weekly"} = job) do
    "#{job.weekday_csv || "mon"}@#{pad(job.run_hour)}:#{pad(job.run_minute)}"
  end

  defp schedule_summary(job), do: "every-#{job.interval_minutes}m"

  defp pad(nil), do: "00"
  defp pad(value) when value < 10, do: "0#{value}"
  defp pad(value), do: to_string(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp resolve_agent(nil), do: HydraX.Runtime.ensure_default_agent!()

  defp resolve_agent(slug) do
    HydraX.Runtime.get_agent_by_slug(slug) || raise "unknown agent #{slug}"
  end

  defp normalize_switches(args) do
    Enum.map(args, fn
      <<"--", rest::binary>> -> "--" <> String.replace(rest, "_", "-")
      other -> other
    end)
  end
end
