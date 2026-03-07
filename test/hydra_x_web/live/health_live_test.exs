defmodule HydraXWeb.HealthLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Memory
  alias HydraX.Runtime

  setup do
    install_root =
      Path.join(System.tmp_dir!(), "hydra-x-health-install-#{System.unique_integer([:positive])}")

    previous_install_root = System.get_env("HYDRA_X_INSTALL_ROOT")
    System.put_env("HYDRA_X_INSTALL_ROOT", install_root)

    on_exit(fn ->
      restore_env("HYDRA_X_INSTALL_ROOT", previous_install_root)
      File.rm_rf(install_root)
    end)

    :ok
  end

  test "health page can filter readiness warnings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/health")

    view
    |> form("form[phx-submit=\"filter_health\"]", %{
      "filters" => %{
        "search" => "password",
        "check_status" => "",
        "readiness_status" => "warn",
        "required_only" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Operator password configured"
    refute html =~ "Primary provider configured"
  end

  test "health page can export an operator report", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/health")

    view
    |> element(~s(button[phx-click="export_report"]))
    |> render_click()

    html = render(view)
    assert html =~ "Operator report exported"
    assert html =~ "hydra-x-report-"
    assert html =~ ".md"
    assert html =~ ".json"
  end

  test "health page shows memory conflict triage", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Daily cadence should win.",
        last_seen_at: DateTime.utc_now()
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Weekly cadence should win.",
        last_seen_at: DateTime.utc_now()
      })

    assert {:ok, _result} = Memory.conflict_memory!(source.id, target.id)

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Conflict review queue"
    assert html =~ "Conflicted"
    assert html =~ ">2<"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
