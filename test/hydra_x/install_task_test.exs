defmodule HydraX.InstallTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  test "install export writes env and note files" do
    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-install-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    Mix.Task.reenable("hydra_x.install")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Install.run(["--output", output_root])
      end)

    env_path = Path.join(output_root, ".env.preview")
    note_path = Path.join(output_root, "README-preview.md")

    assert output =~ "env="
    assert output =~ "note="
    assert output =~ "readiness="
    assert output =~ "persistence=postgres"
    assert output =~ "coordination=database_leases"
    assert output =~ "required_warn="
    assert output =~ "recommended_warn="
    assert File.exists?(env_path)
    assert File.exists?(note_path)
    assert File.read!(env_path) =~ "HYDRA_X_PUBLIC_URL="
    assert File.read!(env_path) =~ "HYDRA_X_REPO_ADAPTER=postgres"
    assert File.read!(env_path) =~ "DATABASE_URL="
    assert File.read!(note_path) =~ "Hydra-X Preview Install Snapshot"
    assert File.read!(note_path) =~ "Persistence backend: postgres"
    assert File.read!(note_path) =~ "Coordination mode: database_leases"
    assert File.read!(note_path) =~ "Summary:"
    assert File.read!(note_path) =~ "Required warnings:"
    assert File.read!(note_path) =~ "Deployment Checklist"
  end
end
