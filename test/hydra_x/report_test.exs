defmodule HydraX.ReportTest do
  use HydraX.DataCase

  alias HydraX.Report
  alias HydraX.Telemetry
  alias HydraX.Safety
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
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "report.md"), "# Report\n\nTrack ingest runs.")
    assert {:ok, _result} = Runtime.ingest_file(agent.id, Path.join(ingest_dir, "report.md"))
    Telemetry.tool_execution("workspace_read", :error, %{})

    {:ok, _event} =
      Safety.log_event(%{
        agent_id: agent.id,
        category: "operator",
        level: "info",
        message: "Generated an audit-ready report"
      })

    assert {:ok, _mcp} =
             Runtime.save_mcp_server(%{
               name: "Docs MCP",
               transport: "stdio",
               command: "cat",
               enabled: true
             })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Report Conversation",
        external_ref: "C999"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "delivered",
          "external_ref" => "C999",
          "provider_message_id" => "999.111",
          "reply_context" => %{
            "thread_ts" => "123.456",
            "source_message_id" => "123.456"
          }
        }
      })

    snapshot = Report.snapshot()

    assert snapshot.default_agent.id == agent.id
    assert is_list(snapshot.health_checks)
    assert is_map(snapshot.readiness)
    assert snapshot.install.public_url
    assert is_list(snapshot.conversations)
    assert is_list(snapshot.agents)
    assert Enum.any?(snapshot.mcp, &(&1.name == "Docs MCP" and &1.status == :ok))
    assert Enum.any?(snapshot.agent_mcp, &(&1.agent_id == agent.id and &1.enabled_bindings == 1))
    assert Enum.any?(snapshot.agents, &(&1.id == agent.id and &1.mcp_count == 1))
    assert is_map(snapshot.incidents)
    assert is_list(snapshot.audit)
    assert Enum.any?(snapshot.ingest, &(&1.source_file == "report.md"))
    assert snapshot.observability.telemetry_summary.tool.error >= 1
    assert Enum.any?(snapshot.observability.telemetry.recent_events, &(&1.namespace == "tool"))
    assert Enum.any?(snapshot.audit, &(&1.category == "operator"))
    assert Enum.any?(snapshot.conversations, &(&1.metadata["last_delivery"]["reply_context"]["thread_ts"] == "123.456"))
  end

  test "export_snapshot writes markdown json and bundle exports" do
    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-report-export-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    agent = Runtime.ensure_default_agent!()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "slack",
        title: "Export Conversation",
        external_ref: "C555"
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "last_delivery" => %{
          "channel" => "slack",
          "status" => "delivered",
          "external_ref" => "C555",
          "provider_message_id" => "555.111",
          "reply_context" => %{
            "thread_ts" => "777.888",
            "source_message_id" => "777.888"
          }
        }
      })

    {:ok, export} = Report.export_snapshot(output_root)

    assert File.exists?(export.markdown_path)
    assert File.exists?(export.json_path)
    assert File.dir?(export.bundle_dir)
    assert File.exists?(Path.join(export.bundle_dir, "manifest.json"))
    assert File.exists?(Path.join(export.bundle_dir, "agents.json"))
    assert File.exists?(Path.join(export.bundle_dir, "mcp.json"))
    assert File.exists?(Path.join(export.bundle_dir, "agent_mcp.json"))
    assert File.exists?(Path.join(export.bundle_dir, "incidents.json"))
    assert File.exists?(Path.join(export.bundle_dir, "audit.json"))
    assert File.read!(export.markdown_path) =~ "Hydra-X Operator Report"
    assert File.read!(export.markdown_path) =~ "Agent Runtime Snapshots"
    assert File.read!(export.markdown_path) =~ "MCP Integrations"
    assert File.read!(export.markdown_path) =~ "Agent MCP Bindings"
    assert File.read!(export.markdown_path) =~ "Audit Trail"
    assert File.read!(export.markdown_path) =~ "Readiness"
    assert File.read!(export.markdown_path) =~ "ctx=777.888/777.888"
    assert File.read!(export.json_path) =~ "\"generated_at\""
    assert File.read!(export.json_path) =~ "\"last_delivery\""
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
