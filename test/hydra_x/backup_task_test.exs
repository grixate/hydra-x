defmodule HydraX.BackupTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "backup task writes a verified archive manifest" do
    agent = Runtime.ensure_default_agent!()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Backup task workspace")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-backup-task-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    Mix.Task.reenable("hydra_x.backup")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Backup.run(["--output", output_root])
      end)

    assert output =~ "backup="
    assert output =~ "manifest="
    assert output =~ "entries="
    assert output =~ "backup_mode=external_database"
    assert output =~ "verified=true"
    assert output =~ "archive_size="
  end

  test "restore task prints restored target and manifest verification status" do
    agent = Runtime.ensure_default_agent!()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Restore task workspace")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-restore-task-#{System.unique_integer([:positive])}")

    restore_root =
      Path.join(System.tmp_dir!(), "hydra-x-restore-target-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf(output_root)
      File.rm_rf(restore_root)
    end)

    {:ok, manifest} = HydraX.Backup.create_bundle(output_root)
    Mix.Task.reenable("hydra_x.restore")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Restore.run([
          "--archive",
          manifest["archive_path"],
          "--target",
          restore_root
        ])
      end)

    assert output =~ "restored_to="
    assert output =~ "manifest="
    assert output =~ "entries="
    assert output =~ "workspaces="
    assert output =~ "backup_mode=external_database"
    assert output =~ "verified="
  end
end
