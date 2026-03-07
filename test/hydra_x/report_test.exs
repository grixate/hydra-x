defmodule HydraX.ReportTest do
  use HydraX.DataCase

  alias HydraX.Report
  alias HydraX.Telemetry
  alias HydraX.Runtime

  setup do
    install_root =
      Path.join(System.tmp_dir!(), "hydra-x-report-install-#{System.unique_integer([:positive])}")

    previous_install_root = System.get_env("HYDRA_X_INSTALL_ROOT")
    System.put_env("HYDRA_X_INSTALL_ROOT", install_root)

    on_exit(fn ->
      restore_env("HYDRA_X_INSTALL_ROOT", previous_install_root)
      File.rm_rf(install_root)
    end)

    :ok
  end

  test "snapshot includes default agent, readiness, and health data" do
    agent = Runtime.ensure_default_agent!()
    Telemetry.tool_execution("workspace_read", :error, %{})
    snapshot = Report.snapshot()

    assert snapshot.default_agent.id == agent.id
    assert is_list(snapshot.health_checks)
    assert is_map(snapshot.readiness)
    assert snapshot.install.public_url
    assert is_list(snapshot.conversations)
    assert snapshot.observability.telemetry_summary.tool.error >= 1
    assert Enum.any?(snapshot.observability.telemetry.recent_events, &(&1.namespace == "tool"))
  end

  test "export_snapshot writes markdown and json reports" do
    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-report-export-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    {:ok, export} = Report.export_snapshot(output_root, only_warn: true, required_only: true)

    assert File.exists?(export.markdown_path)
    assert File.exists?(export.json_path)
    assert File.read!(export.markdown_path) =~ "Hydra-X Operator Report"
    assert File.read!(export.markdown_path) =~ "Readiness"
    assert File.read!(export.json_path) =~ "\"generated_at\""
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
