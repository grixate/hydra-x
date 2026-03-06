defmodule Mix.Tasks.HydraX.Restore do
  use Mix.Task

  @shortdoc "Restores a Hydra-X backup bundle into a target directory"

  @impl true
  def run(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [archive: :string, target: :string],
        aliases: [a: :archive, t: :target]
      )

    archive_path =
      opts[:archive] || List.first(positional) ||
        raise "pass an archive with --archive <path> or as the first positional argument"

    target_root =
      opts[:target] ||
        Path.expand(
          "restore-#{Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")}",
          File.cwd!()
        )

    case HydraX.Backup.restore_bundle(archive_path, target_root) do
      {:ok, result} ->
        manifest = result["manifest"]
        Mix.shell().info("restored_to=#{result["target_root"]}")
        Mix.shell().info("manifest=#{result["manifest_path"]}")
        Mix.shell().info("entries=#{manifest["entry_count"]}")

      {:error, reason} ->
        Mix.raise("restore failed: #{inspect(reason)}")
    end
  end
end
