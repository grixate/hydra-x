defmodule HydraX.BackupTest do
  use HydraX.DataCase

  alias HydraX.Backup
  alias HydraX.Runtime

  test "create_bundle writes a portable archive and manifest" do
    agent = create_agent()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Backup workspace")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-backup-output-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    assert {:ok, manifest} = Backup.create_bundle(output_root)
    assert File.exists?(manifest["archive_path"])
    assert File.exists?(manifest["manifest_path"])
    assert manifest["entry_count"] >= 2
    assert manifest["workspace_count"] >= 1
    assert manifest["verified"] == true
    assert manifest["missing_entries"] == []
    assert manifest["archive_size_bytes"] > 0
    assert manifest["persistence"]["backend"] == "postgres"
    assert manifest["persistence"]["backup_mode"] == "external_database"

    assert Enum.any?(manifest["entries"], &(&1["type"] == "database_reference"))

    assert Enum.any?(
             manifest["entries"],
             &(&1["type"] == "workspace" and &1["agent_slug"] == agent.slug)
           )
  end

  test "restore_bundle extracts the database, workspaces, and manifest" do
    agent = create_agent()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Restore workspace")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-backup-output-#{System.unique_integer([:positive])}")

    restore_root =
      Path.join(System.tmp_dir!(), "hydra-x-restore-output-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf(output_root)
      File.rm_rf(restore_root)
    end)

    {:ok, manifest} = Backup.create_bundle(output_root)

    assert {:ok, result} = Backup.restore_bundle(manifest["archive_path"], restore_root)
    assert File.exists?(result["manifest_path"])

    restored_workspace =
      Path.join([restore_root, "workspaces", agent.slug, "SOUL.md"])

    assert File.read!(restored_workspace) == "Restore workspace"

    database_entry =
      Enum.find(result["manifest"]["entries"], &(&1["type"] == "database_reference"))

    assert File.exists?(Path.join(restore_root, database_entry["bundle_path"]))
  end

  test "verify_bundle confirms portable archives are restorable" do
    agent = create_agent()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Verify workspace")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-backup-output-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    {:ok, manifest} = Backup.create_bundle(output_root)

    assert {:ok, verification} = Backup.verify_bundle(manifest["archive_path"])
    assert verification["verified"]
    assert verification["missing_entries"] == []
    assert verification["entry_count"] == manifest["entry_count"]
  end

  test "create_bundle records an external database reference for postgres persistence" do
    agent = create_agent()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Postgres workspace")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-backup-output-#{System.unique_integer([:positive])}")

    restore_root =
      Path.join(System.tmp_dir!(), "hydra-x-restore-output-#{System.unique_integer([:positive])}")

    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    previous_repo = Application.get_env(:hydra_x, HydraX.Repo)

    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    Application.put_env(:hydra_x, HydraX.Repo,
      url: "ecto://postgres:postgres@db.example.test/hydra_x"
    )

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_repo do
        Application.put_env(:hydra_x, HydraX.Repo, previous_repo)
      else
        Application.delete_env(:hydra_x, HydraX.Repo)
      end

      File.rm_rf(output_root)
      File.rm_rf(restore_root)
    end)

    assert {:ok, manifest} = Backup.create_bundle(output_root)
    assert manifest["persistence"]["backend"] == "postgres"
    assert manifest["persistence"]["backup_mode"] == "external_database"

    database_entry =
      Enum.find(manifest["entries"], &(&1["type"] == "database_reference"))

    assert database_entry["backend"] == "postgres"
    assert database_entry["backup_mode"] == "external_database"
    assert {:ok, _result} = Backup.restore_bundle(manifest["archive_path"], restore_root)
    assert File.exists?(Path.join(restore_root, database_entry["bundle_path"]))
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Backup Agent #{unique}",
        slug: "backup-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-backup-agent-#{unique}"),
        description: "backup test agent",
        is_default: false
      })

    agent
  end
end
