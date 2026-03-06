defmodule Mix.Tasks.HydraX.Backup do
  use Mix.Task

  @shortdoc "Creates a timestamped backup archive with the database and workspaces"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [output: :string], aliases: [o: :output])

    output_root =
      opts[:output] ||
        Path.expand("backups", File.cwd!())

    File.mkdir_p!(output_root)

    archive_path = Path.join(output_root, "hydra-x-backup-#{timestamp()}.tar.gz")

    entries =
      [HydraX.Config.repo_database_path() | workspace_paths()]
      |> Enum.uniq()
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&to_charlist/1)

    case :erl_tar.create(String.to_charlist(archive_path), entries, [:compressed, :dereference]) do
      :ok ->
        Mix.shell().info("backup=#{archive_path}")
        Mix.shell().info("entries=#{length(entries)}")

      {:error, reason} ->
        Mix.raise("backup failed: #{inspect(reason)}")
    end
  end

  defp workspace_paths do
    HydraX.Runtime.list_agents()
    |> Enum.map(& &1.workspace_root)
  end

  defp timestamp do
    Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
  end
end
