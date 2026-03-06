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
      opts[:output] || HydraX.Config.backup_root()

    File.mkdir_p!(output_root)

    stamp = timestamp()
    archive_path = Path.join(output_root, "hydra-x-backup-#{stamp}.tar.gz")
    manifest_path = Path.join(output_root, "hydra-x-backup-#{stamp}.json")

    entries =
      [HydraX.Config.repo_database_path() | workspace_paths()]
      |> Enum.uniq()
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&to_charlist/1)

    case :erl_tar.create(String.to_charlist(archive_path), entries, [:compressed, :dereference]) do
      :ok ->
        File.write!(
          manifest_path,
          Jason.encode_to_iodata!(manifest(archive_path, entries), pretty: true)
        )

        Mix.shell().info("backup=#{archive_path}")
        Mix.shell().info("manifest=#{manifest_path}")
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

  defp manifest(archive_path, entries) do
    %{
      created_at: DateTime.utc_now(),
      archive_path: archive_path,
      entry_count: length(entries),
      entries: Enum.map(entries, &List.to_string/1)
    }
  end
end
