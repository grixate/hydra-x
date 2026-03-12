defmodule HydraXWeb.HealthLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraX.Security.LoginThrottle
  alias HydraX.Telemetry

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
    assert html =~ "Required blockers"
    assert html =~ "Next steps"
    refute html =~ "Primary provider configured"
  end

  test "health page shows operator login throttle policy", %{conn: conn} do
    LoginThrottle.reset!()
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")
    LoginThrottle.record_attempt("127.0.0.1")

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Login throttle"
    assert html =~ "5 attempts per 60s window"
    assert html =~ "blocked IPs 1"
  end

  test "health page shows tool channel policy", %{conn: conn} do
    {:ok, _policy} =
      Runtime.save_tool_policy(%{
        "workspace_write_channels_csv" => "cli,control_plane",
        "http_fetch_channels_csv" => "cli,scheduler",
        "web_search_channels_csv" => "cli",
        "shell_command_channels_csv" => "cli"
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Tool channel policy"
    assert html =~ "write cli, control_plane"
    assert html =~ "http cli, scheduler"
    assert html =~ "shell cli"
  end

  test "health page shows scheduler routing replay summaries", %{conn: conn} do
    Runtime.Jobs.reset_scheduler_passes()

    on_exit(fn ->
      Runtime.Jobs.reset_scheduler_passes()
    end)

    Runtime.Jobs.record_scheduler_pass(:pending_ingress, %{
      owner: "node:test",
      processed_count: 2,
      skipped_count: 1,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:ownership_handoffs, %{
      owner: "node:test",
      resumed_count: 3,
      skipped_count: 1,
      error_count: 0,
      results: []
    })

    Runtime.Jobs.record_scheduler_pass(:deferred_deliveries, %{
      owner: "node:test",
      delivered_count: 4,
      skipped_count: 2,
      error_count: 1,
      results: []
    })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "node:test"
    assert html =~ "Ingress replay"
    assert html =~ "processed 2"
    assert html =~ "Ownership replay"
    assert html =~ "resumed 3"
    assert html =~ "Deferred delivery replay"
    assert html =~ "delivered 4"
  end

  test "health page shows the unified effective policy surface", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Unified decision surface"
    assert html =~ "Provider route"
    assert html =~ "Budget routing"
    assert html =~ "Workload routing"
    assert html =~ "Tool access matrix"
  end

  test "health page shows provider capability summary", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "LLM adapter capabilities"
    assert html =~ "system-prompt"
    assert html =~ "mock"
  end

  test "health page shows secret storage posture", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _provider} =
      Runtime.save_provider_config(%{
        name: "Health Secret Provider",
        kind: "openai_compatible",
        base_url: "https://secret-health.test",
        api_key: "secret",
        model: "gpt-secret-health",
        enabled: false
      })

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        webhook_secret: "hook-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Secret posture"
    assert html =~ "provider"
    assert html =~ "encrypted"
    assert html =~ "key source"
  end

  test "health page shows operator auth audit summaries", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    Enum.each(
      [
        {"Operator login succeeded", "info", %{"ip" => "127.0.0.1"}},
        {"Operator login failed", "warn", %{"ip" => "127.0.0.1"}},
        {"Blocked sensitive action pending re-authentication", "warn", %{}},
        {"Operator session expired", "warn", %{"expired_by" => "idle_timeout"}}
      ],
      fn {message, level, metadata} ->
        {:ok, _event} =
          HydraX.Safety.log_event(%{
            agent_id: agent.id,
            category: "auth",
            level: level,
            message: message,
            metadata: metadata
          })
      end
    )

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Recent auth audit"
    assert html =~ "Sign-ins (24h)"
    assert html =~ "Reauth blocks"
    assert html =~ "Session expiries"
    assert html =~ "idle_timeout"
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

  test "health page shows verified backup inventory", %{conn: conn} do
    {:ok, manifest} = HydraX.Backup.create_bundle(HydraX.Config.backup_root())
    backups = Runtime.backup_status()

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Backup inventory"
    assert html =~ manifest["archive_path"]
    assert html =~ "archive verified"
    assert html =~ "verified #{backups.verified_count}"
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
    assert html =~ "Embedding backend"
    assert html =~ "Fallback writes"
    assert html =~ "Conflicted"
    assert html =~ ">2<"
  end

  test "health page shows recent telemetry summaries", %{conn: conn} do
    Telemetry.provider_request(:error, "Broken Provider", %{})
    Telemetry.gateway_delivery("telegram", :ok, %{})

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Recent telemetry events"
    assert html =~ "Broken Provider"
    assert html =~ "telegram"
  end

  test "health page shows Telegram delivery diagnostics", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        title: "Delayed reply",
        external_ref: "999"
      })

    {:ok, _updated} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "external_ref" => "999",
          "status" => "dead_letter",
          "retry_count" => 1,
          "reason" => "timeout",
          "provider_message_ids" => [501, 502],
          "dead_lettered_at" => "2026-03-11T09:00:00Z",
          "formatted_payload" => %{"chunk_count" => 2}
        }
      })

    {:ok, streaming_conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        title: "Streaming Reply",
        external_ref: "1000"
      })

    {:ok, _updated} =
      Runtime.update_conversation_metadata(streaming_conversation, %{
        "last_delivery" => %{
          "channel" => "telegram",
          "external_ref" => "1000",
          "status" => "streaming",
          "metadata" => %{
            "transport" => "session_pubsub",
            "transport_topic" => "webchat:session:1000"
          },
          "formatted_payload" => %{
            "chunk_count" => 3,
            "text" => "Streaming partial response"
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Retryable failed deliveries: 1"
    assert html =~ "Recent Telegram delivery failures"
    assert html =~ "Active Telegram streams"
    assert html =~ "Delayed reply"
    assert html =~ "Streaming Reply"
    assert html =~ "dead letter 1"
    assert html =~ "multipart 1"
    assert html =~ "streaming 1"
    assert html =~ "chunks 3"
    assert html =~ "transport session_pubsub"
    assert html =~ "topic webchat:session:1000"
    assert html =~ "msg ids 2"
  end

  test "health page shows Discord and Slack channel readiness", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-test-token",
        application_id: "discord-app",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, failed_slack} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Slack Failure",
        external_ref: "C777"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(failed_slack, %{
        "last_delivery" => %{
          "channel" => "slack",
          "external_ref" => "C777",
          "status" => "failed",
          "reason" => "thread timeout",
          "reply_context" => %{"thread_ts" => "123.456"}
        }
      })

    {:ok, streaming_slack} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Slack Stream",
        external_ref: "C778"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(streaming_slack, %{
        "last_delivery" => %{
          "channel" => "slack",
          "external_ref" => "C778",
          "status" => "streaming",
          "formatted_payload" => %{
            "chunk_count" => 4,
            "text" => "Streaming thread preview"
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Additional channel readiness"
    assert html =~ "discord"
    assert html =~ "slack"
    assert html =~ "discord-app"
    assert html =~ "capabilities:"
    assert html =~ "thread timeout"
    assert html =~ "thread 123.456"
    assert html =~ "streaming 1"
    assert html =~ "Active streams"
    assert html =~ "Slack Stream"
  end

  test "health page shows Webchat readiness", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        subtitle: "Public ingress",
        enabled: true,
        allow_anonymous_messages: false,
        session_max_age_minutes: 180,
        session_idle_timeout_minutes: 30,
        attachments_enabled: true,
        max_attachment_count: 2,
        max_attachment_size_kb: 256,
        default_agent_id: agent.id
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Additional channel readiness"
    assert html =~ "webchat"
    assert html =~ "/webchat"
    assert html =~ "policy: identity required"
    assert html =~ "max 180m"
    assert html =~ "idle 30m"
    assert html =~ "attachments 2x256KB"
    assert html =~ "transport session_pubsub"
  end

  test "health page shows MCP server registry health", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, server} =
      Runtime.save_mcp_server(%{
        name: "Docs MCP",
        transport: "stdio",
        command: "cat",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    [binding] = Runtime.list_agent_mcp_servers(agent.id)
    assert binding.mcp_server_config_id == server.id

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "MCP servers"
    assert html =~ "Docs MCP"
    assert html =~ "stdio"
    assert html =~ "healthy"
    assert html =~ "Agent MCP"
    assert html =~ agent.slug
  end

  test "health page shows cluster posture", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Cluster posture"
    assert html =~ "single_node"
    assert html =~ "sqlite_single_writer"
    assert html =~ "Persistence: sqlite"
    assert html =~ "Backup mode: bundled_database"
    assert html =~ "Coordination mode"
    assert html =~ "local_single_node"
  end

  test "health page shows open scheduler circuits", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Circuit Health Job",
        kind: "prompt",
        interval_minutes: 30,
        enabled: true,
        circuit_state: "open",
        consecutive_failures: 2,
        last_failure_reason: "provider offline"
      })

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Open circuits"
    assert html =~ "Open scheduler circuits"
    assert html =~ "Circuit Health Job"
    assert html =~ "provider offline"
  end

  test "health page shows default agent provider warmup readiness", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Warm Health Provider",
        kind: "openai_compatible",
        base_url: "https://health-provider.test",
        api_key: "secret",
        model: "gpt-health",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{"default_provider_id" => provider.id})

    {:ok, _agent, _status} =
      Runtime.warm_agent_provider_routing(agent.id,
        request_fn: fn _opts ->
          {:ok,
           %{
             status: 200,
             body: %{
               "choices" => [
                 %{
                   "message" => %{"content" => "OK", "tool_calls" => nil},
                   "finish_reason" => "stop"
                 }
               ]
             }
           }}
        end
      )

    {:ok, _view, html} = live(conn, ~p"/health")

    assert html =~ "Default agent provider route warmed"
    assert html =~ "hydra-primary: Warm Health Provider via agent_default"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
