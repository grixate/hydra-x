defmodule Mix.Tasks.HydraX.Restore do
  use Mix.Task

  @shortdoc "Restores a Hydra-X backup bundle into a target directory"

  @impl true
  def run(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [archive: :string, target: :string, verify: :boolean],
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

    if opts[:verify] do
      case HydraX.Backup.verify_bundle(archive_path) do
        {:ok, result} ->
          Mix.shell().info("verified=#{result["verified"]}")
          Mix.shell().info("entries=#{result["entry_count"]}")

          if result["missing_entries"] != [] do
            Mix.shell().info("missing=#{Enum.join(result["missing_entries"], ",")}")
          end

        {:error, reason} ->
          Mix.raise("verify failed: #{inspect(reason)}")
      end
    else
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
end
