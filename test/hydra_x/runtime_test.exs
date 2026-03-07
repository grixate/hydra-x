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

  test "chat flow persists turns and memory recall works" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, write_conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "memory-write"})

    write_response =
      Channel.submit(
        agent,
        write_conversation,
        "Remember that the operator prefers terse answers and decisive summaries.",
        %{source: "test"}
      )

    assert write_response =~ "Saved memory"
    assert [%{type: "Preference"} | _] = Memory.search(agent.id, "terse answers", 5)

    {:ok, recall_conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "memory-read"})

    recall_response =
      Channel.submit(
        agent,
        recall_conversation,
        "What do you remember about terse answers?",
        %{source: "test"}
      )

    assert recall_response =~ "Relevant memory"
    assert recall_response =~ "terse answers"
    assert length(Runtime.list_turns(recall_conversation.id)) == 2
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

  test "workspace reads are routed through the worker with path confinement" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Hydra-X workspace directive")

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "workspace-read"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Read file SOUL.md and tell me what it says.",
        %{source: "test"}
      )

    assert response =~ "Workspace file SOUL.md"
    assert response =~ "Hydra-X workspace directive"
  end

  test "workspace traversal attempts are blocked and logged" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "workspace-block"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Read file ../secrets.txt and tell me what it says.",
        %{source: "test"}
      )

    assert response =~ "workspace_read error"

    [event | _] = Safety.recent_events(agent.id, 5)
    assert event.category == "tool"
    assert event.message =~ "workspace_read"
  end

  test "allowlisted shell commands run through the worker" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "shell-command"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Run pwd",
        %{source: "test"}
      )

    assert response =~ "Shell command pwd"
    assert response =~ agent.workspace_root
  end

  test "disallowed shell commands are blocked and logged" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "shell-block"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Run git checkout -b danger",
        %{source: "test"}
      )

    assert response =~ "shell_command error"

    [event | _] = Safety.recent_events(agent.id, 5)
    assert event.category == "tool"
    assert event.message =~ "shell_command"
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

  test "tool policy can disable shell execution at runtime" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _policy} =
      Runtime.save_tool_policy(%{
        shell_command_enabled: false
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "shell-disabled"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Run pwd",
        %{source: "test"}
      )

    assert response =~ "shell_command error"
    assert response =~ ":tool_disabled"
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
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => "OK"}}]}}}
    end

    assert {:ok, %{content: "OK", provider: "OpenAI Test"}} =
             Runtime.test_provider_config(provider, request_fn: request_fn)
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
