defmodule HydraX.ReportTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  test "report task writes markdown and json exports" do
    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-report-task-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Report.run(["--output", output_root, "--required-only", "--only-warn"])
      end)

    assert output =~ "markdown="
    assert output =~ "json="
    assert output =~ "readiness="

    [markdown_path] = Path.wildcard(Path.join(output_root, "*.md"))
    [json_path] = Path.wildcard(Path.join(output_root, "*.json"))

    assert File.read!(markdown_path) =~ "Hydra-X Operator Report"
    assert File.read!(json_path) =~ "\"readiness\""
  end
end
