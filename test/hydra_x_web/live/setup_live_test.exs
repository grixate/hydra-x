defmodule HydraXWeb.SetupLiveTest do
  use HydraXWeb.ConnCase

  setup do
    backup_root =
      Path.join(System.tmp_dir!(), "hydra-x-live-backups-#{System.unique_integer([:positive])}")

    install_root =
      Path.join(System.tmp_dir!(), "hydra-x-live-install-#{System.unique_integer([:positive])}")

    previous_backup_root = System.get_env("HYDRA_X_BACKUP_ROOT")
    previous_install_root = System.get_env("HYDRA_X_INSTALL_ROOT")

    System.put_env("HYDRA_X_BACKUP_ROOT", backup_root)
    System.put_env("HYDRA_X_INSTALL_ROOT", install_root)

    on_exit(fn ->
      restore_env("HYDRA_X_BACKUP_ROOT", previous_backup_root)
      restore_env("HYDRA_X_INSTALL_ROOT", previous_install_root)
      File.rm_rf(backup_root)
      File.rm_rf(install_root)
    end)

    :ok
  end

  test "setup page renders preview readiness report", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/setup")

    assert html =~ "Install preflight"
    assert html =~ "Operator password configured"
    assert html =~ "Public URL points beyond localhost"
  end

  test "setup page can export install artifacts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> element(~s(button[phx-click="export_install"]))
    |> render_click()

    html = render(view)
    assert html =~ "Install bundle exported"
    assert html =~ ".env.preview"
    assert html =~ "README-preview.md"
  end

  test "setup page can create backup bundles", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> element(~s(button[phx-click="create_backup_bundle"]))
    |> render_click()

    html = render(view)
    assert html =~ "Backup bundle created"
    assert html =~ "hydra-x-backup-"
    assert html =~ ".tar.gz"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
