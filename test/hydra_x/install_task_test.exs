defmodule HydraX.InstallTaskTest do
  use HydraX.DataCase

  test "install export writes env and note files" do
    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-install-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    Mix.Tasks.HydraX.Install.run(["--output", output_root])

    env_path = Path.join(output_root, ".env.preview")
    note_path = Path.join(output_root, "README-preview.md")

    assert File.exists?(env_path)
    assert File.exists?(note_path)
    assert File.read!(env_path) =~ "HYDRA_X_PUBLIC_URL="
    assert File.read!(note_path) =~ "Hydra-X Preview Install Snapshot"
  end
end
