defmodule HydraX.RuntimeTest do
  use HydraX.DataCase

  alias HydraX.Agent.Channel
  alias HydraX.Budget
  alias HydraX.Memory
  alias HydraX.Runtime
  alias HydraX.Safety

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

    assert budget.status == :ok
    assert budget.detail =~ "daily"
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
end
