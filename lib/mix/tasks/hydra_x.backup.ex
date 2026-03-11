defmodule Mix.Tasks.HydraX.Backup do
  use Mix.Task

  @shortdoc "Creates a timestamped backup archive with the database and workspaces"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HydraX.Runtime.ensure_default_agent!()

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [output: :string, verify: :boolean], aliases: [o: :output])

    output_root =
      opts[:output] || HydraX.Config.backup_root()

    {:ok, manifest} = HydraX.Backup.create_bundle(output_root, verify: opts[:verify] != false)
    Mix.shell().info("backup=#{manifest["archive_path"]}")
    Mix.shell().info("manifest=#{manifest["manifest_path"]}")
    Mix.shell().info("entries=#{manifest["entry_count"]}")

    Mix.shell().info(
      "backup_mode=#{get_in(manifest, ["persistence", "backup_mode"]) || "bundled_database"}"
    )

    Mix.shell().info("verified=#{manifest["verified"]}")
    Mix.shell().info("archive_size=#{manifest["archive_size_bytes"] || 0}")

    if (manifest["missing_entries"] || []) != [] do
      Mix.shell().info("missing=#{Enum.join(manifest["missing_entries"], ",")}")
    end
  end
end
