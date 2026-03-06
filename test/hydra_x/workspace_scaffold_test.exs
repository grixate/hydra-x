defmodule HydraX.WorkspaceScaffoldTest do
  use ExUnit.Case, async: true

  test "copies the workspace contract files" do
    destination =
      Path.join(System.tmp_dir!(), "hydra-x-workspace-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(destination) end)

    HydraX.Workspace.Scaffold.copy_template!(destination)

    assert File.exists?(Path.join(destination, "SOUL.md"))
    assert File.exists?(Path.join(destination, "IDENTITY.md"))
    assert File.exists?(Path.join(destination, "memory/MEMORY.md"))
    assert File.exists?(Path.join(destination, "skills/README.md"))
  end
end
