defmodule HydraX.HealthTasksTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  test "healthcheck task can filter warn checks" do
    Mix.Task.reenable("hydra_x.healthcheck")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Healthcheck.run(["--only-warn", "--search", "control plane"])
      end)

    assert output =~ "[WARN] auth:"
    refute output =~ "[OK] database:"
  end

  test "doctor task can filter required warn readiness items" do
    Mix.Task.reenable("hydra_x.doctor")

    output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Doctor.run(["--required-only", "--only-warn"])
      end)

    assert output =~ "readiness=WARN"
    assert output =~ "Operator password configured"
    refute output =~ "Primary provider configured"
  end
end
