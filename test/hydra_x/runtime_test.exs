defmodule HydraX.RuntimeTest do
  use HydraX.DataCase

  alias HydraX.Agent.Channel
  alias HydraX.Budget
  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraX.Safety

  setup do
    backup_root =
      Path.join(System.tmp_dir!(), "hydra-x-test-backups-#{System.unique_integer([:positive])}")

    install_root =
      Path.join(System.tmp_dir!(), "hydra-x-test-install-#{System.unique_integer([:positive])}")

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

  test "chat flow persists turns with mock provider" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "basic-chat"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Hello, how are you?",
        %{source: "test"}
      )

    assert response =~ "Mock response"
    assert response =~ "Hello, how are you?"
    assert length(Runtime.list_turns(conversation.id)) == 2
  end

  test "memory tools work directly" do
    agent = create_agent()

    {:ok, result} =
      HydraX.Tools.MemorySave.execute(
        %{
          agent_id: agent.id,
          type: "Preference",
          content: "The operator prefers terse answers and decisive summaries."
        },
        %{}
      )

    assert result.type == "Preference"
    assert [%{type: "Preference"} | _] = Memory.search(agent.id, "terse answers", 5)

    {:ok, recall} =
      HydraX.Tools.MemoryRecall.execute(%{agent_id: agent.id, query: "terse answers"}, %{})

    assert length(recall.results) > 0
    assert hd(recall.results).content =~ "terse answers"
  end

  test "budget hard limit rejects llm traffic and logs a safety event" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    policy = Budget.ensure_policy!(agent.id)

    {:ok, _updated} =
      Budget.save_policy(policy, %{
        agent_id: agent.id,
        daily_limit: 5,
        conversation_limit: 5,
        soft_warning_at: 0.5,
        hard_limit_action: "reject",
        enabled: true
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "budget-guard"})

    response =
      Channel.submit(
        agent,
        conversation,
        "This message is intentionally long enough to blow past a five token budget limit immediately.",
        %{source: "test"}
      )

    assert response =~ "Budget limit reached"

    [event | _] = Safety.recent_events(agent.id, 5)
    assert event.category == "budget"
    assert event.level == "error"
  end

  test "budget warn mode allows completion and logs a warning event" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    policy = Budget.ensure_policy!(agent.id)

    {:ok, _updated} =
      Budget.save_policy(policy, %{
        agent_id: agent.id,
        daily_limit: 5,
        conversation_limit: 5,
        soft_warning_at: 0.5,
        hard_limit_action: "warn",
        enabled: true
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "budget-warn"})

    response =
      Channel.submit(
        agent,
        conversation,
        "This message is intentionally long enough to exceed the configured hard limit while still allowing warn mode to continue.",
        %{source: "test"}
      )

    refute response =~ "Budget limit reached"

    [event | _] = Safety.recent_events(agent.id, 5)
    assert event.category == "budget"
    assert event.level == "warn"
    assert event.message =~ "warn only"
  end

  test "health snapshot ensures a default budget policy exists" do
    agent = Runtime.ensure_default_agent!()
    assert is_nil(Budget.get_policy(agent.id))

    checks = Runtime.health_snapshot()
    budget = Enum.find(checks, &(&1.name == "budget"))
    auth = Enum.find(checks, &(&1.name == "auth"))
    tools = Enum.find(checks, &(&1.name == "tools"))

    assert budget.status == :ok
    assert budget.detail =~ "daily"
    assert auth.status == :warn
    assert auth.detail =~ "control plane open"
    assert tools.status == :ok
    assert tools.detail =~ "shell allowlist"
    assert Budget.get_policy(agent.id)
  end

  test "health and readiness warn when conflicted memories exist" do
    agent = Runtime.ensure_default_agent!()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Daily review should be authoritative."
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Weekly review should be authoritative."
      })

    assert {:ok, _result} =
             Memory.conflict_memory!(source.id, target.id, reason: "Open memory disagreement")

    memory_check =
      Runtime.health_snapshot()
      |> Enum.find(&(&1.name == "memory"))

    readiness_item =
      Runtime.readiness_report().items
      |> Enum.find(&(&1.id == "memory_conflicts"))

    assert memory_check.status == :warn
    assert memory_check.detail =~ "conflicted 2"
    assert readiness_item.status == :warn
    assert readiness_item.detail =~ "conflicted memories"
  end

  test "resolving a memory conflict clears the conflict and resolves its safety event" do
    agent = create_agent()

    {:ok, winner} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Daily review is canonical."
      })

    {:ok, loser} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Weekly review is canonical."
      })

    assert {:ok, _conflicted} =
             Memory.conflict_memory!(winner.id, loser.id, reason: "Operator disagreement")

    [event | _] = Safety.recent_events(agent.id, 5)
    assert event.category == "memory"
    assert event.status == "open"

    assert {:ok, resolved} =
             Memory.resolve_conflict!(winner.id, loser.id,
               content: "Daily review remains canonical.",
               note: "Operator settled the dispute."
             )

    assert resolved.winner.status == "active"
    assert resolved.loser.status == "superseded"
    assert Memory.get_memory!(winner.id).content == "Daily review remains canonical."

    resolved_event = Safety.get_event!(event.id)
    assert resolved_event.status == "resolved"
    assert resolved_event.resolved_by == "memory_reconciliation"
    assert resolved_event.operator_note =~ "Operator settled the dispute."

    refute Map.has_key?(Memory.get_memory!(winner.id).metadata || %{}, "conflict_reason")
    assert Enum.any?(Memory.list_edges_for(winner.id), &(&1.kind == "supersedes"))
  end

  test "workspace read tool returns file contents within workspace" do
    agent = create_agent()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Hydra-X workspace directive")

    {:ok, result} =
      HydraX.Tools.WorkspaceRead.execute(
        %{path: "SOUL.md"},
        %{workspace_root: agent.workspace_root}
      )

    assert result.path == "SOUL.md"
    assert result.excerpt =~ "Hydra-X workspace directive"
  end

  test "workspace read tool blocks path traversal" do
    agent = create_agent()

    assert {:error, _reason} =
             HydraX.Tools.WorkspaceRead.execute(
               %{path: "../secrets.txt"},
               %{workspace_root: agent.workspace_root}
             )
  end

  test "allowlisted shell commands execute successfully" do
    agent = create_agent()

    {:ok, result} =
      HydraX.Tools.ShellCommand.execute(
        %{command: "pwd"},
        %{workspace_root: agent.workspace_root, shell_allowlist: ["pwd", "ls"]}
      )

    assert result.command == "pwd"
    assert result.output =~ agent.workspace_root
    assert result.exit_status == 0
  end

  test "disallowed shell commands are blocked" do
    agent = create_agent()

    assert {:error, _reason} =
             HydraX.Tools.ShellCommand.execute(
               %{command: "git checkout -b danger"},
               %{workspace_root: agent.workspace_root, shell_allowlist: ["pwd", "ls"]}
             )
  end

  test "health snapshot warns when recent safety events exist" do
    agent = create_agent()

    assert {:ok, _event} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "tool",
               level: "warn",
               message: "blocked tool test"
             })

    safety_check =
      Runtime.health_snapshot()
      |> Enum.find(&(&1.name == "safety"))

    assert safety_check.status == :warn
    assert safety_check.detail =~ "warnings"
  end

  test "safety status accepts level filters" do
    agent = create_agent()

    assert {:ok, _warn} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "tool",
               level: "warn",
               message: "warn event"
             })

    assert {:ok, _error} =
             Safety.log_event(%{
               agent_id: agent.id,
               category: "gateway",
               level: "error",
               message: "error event"
             })

    status = Runtime.safety_status(level: "error", limit: 10)

    assert Enum.all?(status.recent_events, &(&1.level == "error"))
    assert Enum.any?(status.categories, &(&1 == "gateway"))
  end

  test "health snapshot reports operator auth once configured" do
    assert {:ok, _secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    auth_check =
      Runtime.health_snapshot()
      |> Enum.find(&(&1.name == "auth"))

    assert auth_check.status == :ok
    assert auth_check.detail =~ "operator password set"
  end

  test "system status exposes the repo database path" do
    system = Runtime.system_status()

    assert is_binary(system.database_path)
    assert String.ends_with?(system.database_path, ".db")
    assert is_list(system.alarms)
  end

  test "backup status reports recent backup manifests" do
    backup_root = HydraX.Config.backup_root()
    File.mkdir_p!(backup_root)

    manifest_path = Path.join(backup_root, "hydra-x-backup-test.json")

    File.write!(
      manifest_path,
      Jason.encode_to_iodata!(%{
        created_at: "2026-03-07T00:00:00Z",
        archive_path: "/tmp/hydra-x-backup-test.tar.gz",
        entry_count: 2,
        entries: ["/tmp/db", "/tmp/workspace"]
      })
    )

    on_exit(fn -> File.rm_rf(manifest_path) end)

    backups = Runtime.backup_status()

    assert backups.latest_backup["archive_path"] == "/tmp/hydra-x-backup-test.tar.gz"
    refute backups.latest_backup["archive_exists"]
    assert backups.root == backup_root
  end

  test "readiness report marks required local-only setup as warnings" do
    report = Runtime.readiness_report()

    assert report.summary == :warn

    public_url =
      report.items
      |> Enum.find(&(&1.id == "public_url"))

    assert public_url.required
    assert public_url.status == :warn
  end

  test "install snapshot exposes deployment paths and readiness" do
    snapshot = Runtime.install_snapshot()

    assert is_binary(snapshot.public_url)
    assert is_binary(snapshot.database_path)
    assert is_binary(snapshot.workspace_root)
    assert is_binary(snapshot.backup_root)
    assert is_map(snapshot.readiness)
  end

  test "heartbeat jobs are ensured once and create persisted job runs" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    File.write!(
      Path.join(agent.workspace_root, "HEARTBEAT.md"),
      "Review the workspace heartbeat."
    )

    job = Runtime.ensure_heartbeat_job!(agent.id)
    same_job = Runtime.ensure_heartbeat_job!(agent.id)

    assert job.id == same_job.id

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"
    assert run.metadata["conversation_id"]

    conversation = Runtime.get_conversation!(run.metadata["conversation_id"])
    assert conversation.channel == "scheduler"

    [job_run | _] = Runtime.list_job_runs(job.id, 5)
    assert job_run.id == run.id
  end

  test "backup jobs are ensured once and create portable backup artifacts" do
    agent = create_agent()

    job = Runtime.ensure_backup_job!(agent.id)
    same_job = Runtime.ensure_backup_job!(agent.id)

    assert job.id == same_job.id
    assert job.kind == "backup"

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"
    assert run.metadata["archive_path"]
    assert run.metadata["manifest_path"]
    assert File.exists?(run.metadata["archive_path"])
    assert File.exists?(run.metadata["manifest_path"])
  end

  test "scheduled jobs can deliver run results to Telegram" do
    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(self(), {:job_delivery, payload})
      {:ok, %{provider_message_id: 77}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    agent = create_agent()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Backup delivery",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        delivery_enabled: true,
        delivery_channel: "telegram",
        delivery_target: "9001"
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert_receive {:job_delivery, %{external_ref: "9001", content: content}}
    assert content =~ "finished with success"
    assert run.metadata["delivery"]["status"] == "delivered"
    assert run.metadata["delivery"]["metadata"]["provider_message_id"] == 77
  end

  test "weekly scheduled jobs compute the next run after execution" do
    agent = create_agent()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Weekly review",
        kind: "prompt",
        schedule_mode: "weekly",
        weekday_csv: "mon,wed",
        run_hour: 9,
        run_minute: 30,
        prompt: "Weekly review",
        enabled: true
      })

    assert job.schedule_mode == "weekly"
    assert job.weekday_csv == "mon,wed"
    assert job.run_hour == 9
    assert job.run_minute == 30
    assert job.next_run_at

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"

    updated = Runtime.get_scheduled_job!(job.id)
    assert DateTime.compare(updated.next_run_at, DateTime.utc_now()) == :gt
  end

  test "daily scheduled jobs compute the next run after execution" do
    agent = create_agent()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Daily review",
        kind: "prompt",
        schedule_mode: "daily",
        run_hour: 8,
        run_minute: 45,
        prompt: "Daily review",
        enabled: true
      })

    assert job.schedule_mode == "daily"
    assert job.run_hour == 8
    assert job.run_minute == 45
    assert job.next_run_at

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"

    updated = Runtime.get_scheduled_job!(job.id)
    assert DateTime.compare(updated.next_run_at, DateTime.utc_now()) == :gt
  end

  test "tool policy disables tools in the registry" do
    {:ok, _policy} =
      Runtime.save_tool_policy(%{
        shell_command_enabled: false
      })

    policy = Runtime.effective_tool_policy()
    schemas = HydraX.Tool.Registry.available_schemas(policy)
    tool_names = Enum.map(schemas, & &1.name)

    refute "shell_command" in tool_names
    assert "memory_recall" in tool_names
    assert "http_fetch" in tool_names

    # Re-enable
    {:ok, _policy} = Runtime.save_tool_policy(%{shell_command_enabled: true})
    policy = Runtime.effective_tool_policy()
    schemas = HydraX.Tool.Registry.available_schemas(policy)
    tool_names = Enum.map(schemas, & &1.name)
    assert "shell_command" in tool_names
  end

  test "provider failures return an assistant error instead of crashing the channel" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _provider} =
      Runtime.save_provider_config(%{
        name: "Broken Provider",
        kind: "openai_compatible",
        base_url: "http://127.0.0.1:1",
        api_key: "secret",
        model: "gpt-test",
        enabled: true
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "provider-error"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Hello through a broken provider.",
        %{source: "test"}
      )

    assert response =~ "Provider request failed"

    [event | _] = Safety.recent_events(agent.id, 5)
    assert event.category == "provider"
    assert event.level == "error"
  end

  test "provider connectivity tests run through the selected adapter" do
    provider = %Runtime.ProviderConfig{
      name: "OpenAI Test",
      kind: "openai_compatible",
      base_url: "https://example.test",
      api_key: "secret",
      model: "gpt-test"
    }

    request_fn = fn opts ->
      assert opts[:json][:model] == "gpt-test"
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => "OK"}, "finish_reason" => "stop"}]}}}
    end

    assert {:ok, %{content: "OK", provider: "OpenAI Test"}} =
             Runtime.test_provider_config(provider, request_fn: request_fn)
  end

  test "default agent can be reassigned and workspace repaired" do
    agent = create_agent()
    soul_path = Path.join(agent.workspace_root, "SOUL.md")
    File.rm_rf!(soul_path)

    updated = Runtime.set_default_agent!(agent.id)
    Runtime.repair_agent_workspace!(agent.id)

    assert updated.is_default
    assert Runtime.get_default_agent().id == agent.id
    assert File.exists?(soul_path)
  end

  test "agent bulletins can be rebuilt from typed memory" do
    agent = create_agent()

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Hydra-X keeps a typed graph memory."
      })

    bulletin = Runtime.refresh_agent_bulletin!(agent.id)

    assert bulletin.memory_count >= 1
    assert bulletin.content =~ "typed graph memory"
    assert Runtime.agent_bulletin(agent.id).content =~ "typed graph memory"
  end

  test "non-active memories are excluded from active bulletin and markdown exports" do
    agent = create_agent()

    {:ok, source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Deprecated operator preference",
        importance: 0.5
      })

    {:ok, target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Preference",
        content: "Current operator preference",
        importance: 0.9
      })

    assert {:ok, _result} = Memory.reconcile_memory!(source.id, target.id, :supersede)

    bulletin = Runtime.refresh_agent_bulletin!(agent.id)
    markdown = Memory.render_markdown(agent.id)

    assert bulletin.content =~ "Current operator preference"
    refute bulletin.content =~ "Deprecated operator preference"
    assert markdown =~ "Current operator preference"
    refute markdown =~ "Deprecated operator preference"

    {:ok, conflicting_source} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Backups should run daily.",
        importance: 0.6
      })

    {:ok, conflicting_target} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Backups should run weekly.",
        importance: 0.7
      })

    assert {:ok, _result} =
             Memory.conflict_memory!(conflicting_source.id, conflicting_target.id,
               reason: "Open operator dispute"
             )

    refreshed_bulletin = Runtime.refresh_agent_bulletin!(agent.id)
    refreshed_markdown = Memory.render_markdown(agent.id)

    refute refreshed_bulletin.content =~ "Backups should run daily."
    refute refreshed_bulletin.content =~ "Backups should run weekly."
    refute refreshed_markdown =~ "Backups should run daily."
    refute refreshed_markdown =~ "Backups should run weekly."
  end

  test "conversation compaction can be reviewed and reset" do
    agent = create_agent()

    policy =
      Runtime.save_compaction_policy!(agent.id, %{"soft" => 4, "medium" => 8, "hard" => 12})

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "control_plane", title: "Compaction Thread"})

    Enum.each(1..12, fn index ->
      {:ok, _turn} =
        Runtime.append_turn(conversation, %{
          role: if(rem(index, 2) == 0, do: "assistant", else: "user"),
          content: "Turn #{index} for compaction coverage",
          metadata: %{}
        })
    end)

    compaction = Runtime.review_conversation_compaction!(conversation.id)

    assert compaction.turn_count == 12
    assert compaction.level == "hard"
    assert compaction.summary =~ "Turn"
    assert compaction.thresholds == policy

    reset = Runtime.reset_conversation_compaction!(conversation.id)
    assert reset.level == nil
    assert reset.summary == nil
    assert reset.thresholds == policy
  end

  test "compaction policy must remain ordered" do
    agent = create_agent()

    assert_raise ArgumentError, ~r/soft < medium < hard/, fn ->
      Runtime.save_compaction_policy!(agent.id, %{"soft" => 12, "medium" => 8, "hard" => 16})
    end
  end

  test "operator-driven runtime actions are logged to the safety ledger" do
    agent = create_agent()

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Hydra-X records operator actions."
      })

    Runtime.refresh_agent_bulletin!(agent.id)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "control_plane", title: "Audit Thread"})

    Enum.each(1..12, fn index ->
      {:ok, _turn} =
        Runtime.append_turn(conversation, %{
          role: if(rem(index, 2) == 0, do: "assistant", else: "user"),
          content: "Audit turn #{index}",
          metadata: %{}
        })
    end)

    _compaction = Runtime.review_conversation_compaction!(conversation.id)
    _export = Runtime.export_conversation_transcript!(conversation.id)

    events = Safety.list_events(level: "info", category: "operator", limit: 10)

    assert Enum.any?(events, &String.contains?(&1.message, "Refreshed bulletin"))
    assert Enum.any?(events, &String.contains?(&1.message, "Reviewed compaction"))
    assert Enum.any?(events, &String.contains?(&1.message, "Exported transcript"))
  end

  test "runtime reconciliation starts active agents and stops paused agents" do
    {:ok, active_agent} =
      Runtime.save_agent(%{
        name: "Active Agent",
        slug: "active-agent-#{System.unique_integer([:positive])}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-active-agent"),
        description: "active agent",
        is_default: false,
        status: "active"
      })

    {:ok, paused_agent} =
      Runtime.save_agent(%{
        name: "Paused Agent",
        slug: "paused-agent-#{System.unique_integer([:positive])}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-paused-agent"),
        description: "paused agent",
        is_default: false,
        status: "paused"
      })

    Runtime.start_agent_runtime!(paused_agent.id)
    refute HydraX.Agent.running?(active_agent)
    assert HydraX.Agent.running?(paused_agent)

    summary = Runtime.reconcile_agents!()

    assert summary.started >= 1
    assert summary.stopped >= 1
    assert HydraX.Agent.running?(active_agent)
    refute HydraX.Agent.running?(paused_agent)
  end

  test "safety events can be acknowledged, resolved, and reopened" do
    agent = create_agent()

    {:ok, event} =
      Safety.log_event(%{
        agent_id: agent.id,
        category: "gateway",
        level: "error",
        message: "delivery failed"
      })

    acknowledged = Safety.acknowledge_event!(event.id, "operator", "investigating")
    assert acknowledged.status == "acknowledged"
    assert acknowledged.acknowledged_by == "operator"
    assert acknowledged.operator_note == "investigating"

    resolved = Safety.resolve_event!(event.id, "operator", "delivery restored")
    assert resolved.status == "resolved"
    assert resolved.resolved_by == "operator"
    assert resolved.operator_note == "delivery restored"

    reopened = Safety.reopen_event!(event.id, "operator", "regression")
    assert reopened.status == "open"
    assert reopened.acknowledged_by == nil
    assert reopened.resolved_by == nil
    assert reopened.operator_note == "regression"
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Test Agent #{unique}",
        slug: "test-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-agent-#{unique}"),
        description: "test agent",
        is_default: false
      })

    HydraX.Budget.ensure_policy!(agent.id)
    agent
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
