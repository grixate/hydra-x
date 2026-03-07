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

    assert Enum.any?(manifest["entries"], &(&1["type"] == "database"))

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

    database_entry = Enum.find(result["manifest"]["entries"], &(&1["type"] == "database"))
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
