defmodule HydraX.Backup do
  @moduledoc """
  Creates and restores portable backup bundles for Hydra-X.
  """

  alias HydraX.Config
  alias HydraX.Runtime

  @manifest_name "manifest.json"

  def create_bundle(output_root) do
    File.mkdir_p!(output_root)

    stamp = timestamp()
    bundle_name = "hydra-x-backup-#{stamp}"
    archive_path = Path.join(output_root, "#{bundle_name}.tar.gz")
    manifest_path = Path.join(output_root, "#{bundle_name}.json")
    staging_root = Path.join(System.tmp_dir!(), "#{bundle_name}-staging")

    File.rm_rf!(staging_root)
    File.mkdir_p!(staging_root)

    manifest =
      try do
        entries = collect_entries(staging_root)
        manifest = build_manifest(archive_path, entries)

        File.write!(
          Path.join(staging_root, @manifest_name),
          Jason.encode_to_iodata!(manifest, pretty: true)
        )

        create_archive!(archive_path, staging_root)

        File.write!(manifest_path, Jason.encode_to_iodata!(manifest, pretty: true))
        Map.put(manifest, "manifest_path", manifest_path)
      after
        File.rm_rf(staging_root)
      end

    {:ok, manifest}
  end

  def restore_bundle(archive_path, target_root) do
    File.mkdir_p!(target_root)

    char_archive = String.to_charlist(Path.expand(archive_path))
    char_target = String.to_charlist(Path.expand(target_root))

    case :erl_tar.extract(char_archive, [:compressed, cwd: char_target]) do
      :ok ->
        manifest_path = Path.join(target_root, @manifest_name)

        with {:ok, body} <- File.read(manifest_path),
             {:ok, manifest} <- Jason.decode(body) do
          {:ok,
           %{
             "target_root" => Path.expand(target_root),
             "manifest_path" => manifest_path,
             "manifest" => manifest
           }}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_manifests(root \\ Config.backup_root()) do
    root
    |> Path.join("hydra-x-backup-*.json")
    |> Path.wildcard()
    |> Enum.sort(:desc)
    |> Enum.map(&read_manifest/1)
    |> Enum.reject(&is_nil/1)
  end

  def read_manifest(path) do
    with {:ok, body} <- File.read(path),
         {:ok, manifest} <- Jason.decode(body) do
      Map.put(manifest, "manifest_path", path)
    else
      _ -> nil
    end
  end

  defp collect_entries(staging_root) do
    database_root = Path.join(staging_root, "database")
    workspace_root = Path.join(staging_root, "workspaces")

    File.mkdir_p!(database_root)
    File.mkdir_p!(workspace_root)

    database_source = Config.repo_database_path()
    database_target = Path.join(database_root, Path.basename(database_source))
    File.cp!(database_source, database_target)

    workspace_entries =
      Runtime.list_agents()
      |> Enum.map(fn agent ->
        target = Path.join(workspace_root, agent.slug)
        copy_tree!(agent.workspace_root, target)

        %{
          "type" => "workspace",
          "agent_id" => agent.id,
          "agent_slug" => agent.slug,
          "source_path" => agent.workspace_root,
          "bundle_path" => relative_to_staging(target, staging_root)
        }
      end)

    [
      %{
        "type" => "database",
        "source_path" => database_source,
        "bundle_path" => relative_to_staging(database_target, staging_root)
      }
      | workspace_entries
    ]
  end

  defp build_manifest(archive_path, entries) do
    %{
      "created_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "archive_path" => archive_path,
      "entry_count" => length(entries),
      "entries" => entries
    }
  end

  defp create_archive!(archive_path, staging_root) do
    archive_path = Path.expand(archive_path)

    files =
      staging_root
      |> Path.join("*")
      |> Path.wildcard()
      |> Enum.map(&String.to_charlist(Path.basename(&1)))

    result =
      File.cd!(staging_root, fn ->
        :erl_tar.create(String.to_charlist(archive_path), files, [:compressed])
      end)

    case result do
      :ok -> :ok
      {:error, reason} -> raise "backup failed: #{inspect(reason)}"
    end
  end

  defp copy_tree!(source, target) do
    File.rm_rf!(target)
    File.cp_r!(source, target)
  end

  defp relative_to_staging(path, staging_root) do
    Path.relative_to(path, staging_root)
  end

  defp timestamp do
    Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
  end
end
