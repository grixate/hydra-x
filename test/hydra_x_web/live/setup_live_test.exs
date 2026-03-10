defmodule HydraXWeb.SetupLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraXWeb.OperatorAuth

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

  test "setup page can save the global control policy", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("form[phx-submit=\"save_control_policy\"]", %{
      "control_policy" => %{
        "require_recent_auth_for_sensitive_actions" => "true",
        "recent_auth_window_minutes" => "7",
        "interactive_delivery_channels_csv" => "telegram,webchat",
        "job_delivery_channels_csv" => "discord,slack",
        "ingest_roots_csv" => "ingest,docs"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Control policy updated"

    policy = Runtime.effective_control_policy()
    assert policy.recent_auth_window_minutes == 7
    assert policy.job_delivery_channels == ["discord", "slack"]
    assert policy.ingest_roots == ["ingest", "docs"]
  end

  test "setup page requires recent auth for sensitive actions when password is configured", %{
    conn: conn
  } do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    now = System.system_time(:second)

    conn =
      conn
      |> init_test_session(%{})
      |> OperatorAuth.log_in(
        authenticated_at: now,
        last_active_at: now,
        recent_auth_at: now - OperatorAuth.recent_auth_window_seconds() - 10
      )

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> element(~s(button[phx-click="export_install"]))
    |> render_click()

    assert_redirect(view, "/login?reauth=1")

    [event | _] = Safety.list_events(category: "auth", limit: 5)
    assert event.level == "warn"
    assert event.message =~ "Blocked sensitive action pending re-authentication"
  end

  test "setup page can send a Telegram delivery smoke test", %{conn: conn} do
    previous = Application.get_env(:hydra_x, :telegram_deliver)
    test_pid = self()

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(test_pid, {:setup_telegram_test, payload})
      {:ok, %{provider_message_id: 999}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    agent = Runtime.ensure_default_agent!()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("form[phx-submit=\"test_telegram_delivery\"]", %{
      "telegram_test" => %{
        "chat_id" => "4242",
        "message" => "UI smoke test"
      }
    })
    |> render_submit()

    assert_receive {:setup_telegram_test, %{text: "UI smoke test", chat_id: "4242"}}

    html = render(view)
    assert html =~ "Telegram delivery test succeeded"
    assert html =~ "provider_message_id"
  end

  test "setup page can send a Discord delivery smoke test", %{conn: conn} do
    previous = Application.get_env(:hydra_x, :discord_deliver)
    test_pid = self()

    Application.put_env(:hydra_x, :discord_deliver, fn payload ->
      send(test_pid, {:setup_discord_test, payload})
      {:ok, %{provider_message_id: "discord-smoke"}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :discord_deliver, previous)
      else
        Application.delete_env(:hydra_x, :discord_deliver)
      end
    end)

    agent = Runtime.ensure_default_agent!()

    {:ok, _discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-test-token",
        application_id: "discord-app",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("form[phx-submit=\"test_discord_delivery\"]", %{
      "discord_test" => %{
        "target" => "discord-room",
        "message" => "Discord UI smoke test"
      }
    })
    |> render_submit()

    assert_receive {:setup_discord_test,
                    %{content: "Discord UI smoke test", channel_id: "discord-room"}}

    html = render(view)
    assert html =~ "Discord delivery test succeeded"
    assert html =~ "discord-smoke"
  end

  test "setup page can send a Slack delivery smoke test", %{conn: conn} do
    previous = Application.get_env(:hydra_x, :slack_deliver)
    test_pid = self()

    Application.put_env(:hydra_x, :slack_deliver, fn payload ->
      send(test_pid, {:setup_slack_test, payload})
      {:ok, %{provider_message_id: "slack-smoke"}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :slack_deliver, previous)
      else
        Application.delete_env(:hydra_x, :slack_deliver)
      end
    end)

    agent = Runtime.ensure_default_agent!()

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("form[phx-submit=\"test_slack_delivery\"]", %{
      "slack_test" => %{
        "target" => "slack-room",
        "message" => "Slack UI smoke test"
      }
    })
    |> render_submit()

    assert_receive {:setup_slack_test,
                    %{text: "Slack UI smoke test", channel: "slack-room"}}

    html = render(view)
    assert html =~ "Slack delivery test succeeded"
    assert html =~ "slack-smoke"
  end

  test "setup page can save Webchat settings", %{conn: conn} do
    Runtime.ensure_default_agent!()

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("form[phx-submit=\"save_webchat\"]", %{
      "webchat_config" => %{
        "title" => "Hydra-X Browser",
        "subtitle" => "Public ingress",
        "welcome_prompt" => "Welcome to the browser channel.",
        "composer_placeholder" => "Start typing",
        "enabled" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Webchat updated"
    assert html =~ "/webchat"
    assert html =~ "Hydra-X Browser"

    assert %{enabled: true, title: "Hydra-X Browser"} = Runtime.enabled_webchat_config()
  end

  test "setup page can save and test an MCP server", %{conn: conn} do
    previous = Application.get_env(:hydra_x, :mcp_http_request_fn)
    test_pid = self()

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      send(test_pid, {:setup_mcp_test, opts})
      {:ok, %{status: 200}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("form[phx-submit=\"save_mcp_server\"]", %{
      "mcp_server_config" => %{
        "name" => "Docs MCP",
        "transport" => "http",
        "url" => "https://mcp.example.test",
        "healthcheck_path" => "/health",
        "auth_token" => "mcp-secret",
        "retry_limit" => "1",
        "enabled" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "MCP server updated"
    assert html =~ "Docs MCP"

    [server] = Runtime.list_mcp_servers()

    view
    |> element(~s(button[phx-click="test_mcp_server"][phx-value-id="#{server.id}"]))
    |> render_click()

    assert_receive {:setup_mcp_test, opts}
    assert opts[:url] == "https://mcp.example.test/health"

    html = render(view)
    assert html =~ "MCP server test succeeded"
    assert html =~ "HTTP 200"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
