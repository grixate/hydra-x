defmodule HydraX.RuntimeTest do
  use HydraX.DataCase

  alias HydraX.Agent.Channel
  alias HydraX.Agent.Worker
  alias HydraX.Budget
  alias HydraX.Memory
  alias HydraX.Repo
  alias HydraX.Runtime
  alias HydraX.Runtime.{DiscordConfig, ProviderConfig, SlackConfig, TelegramConfig}
  alias HydraX.Security.Secrets
  alias HydraX.Safety
  alias HydraXWeb.OperatorAuth

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

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "completed"
    assert channel_state.plan["mode"] == "tool_capable"
    assert channel_state.provider == "mock"
    assert Enum.all?(channel_state.steps, &(&1["status"] == "completed"))
    assert channel_state.current_step_id == nil
    refute channel_state.resumable
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "provider_requested"))
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "provider_completed"))
  end

  test "worker results include tool summaries and safety classifications" do
    agent = create_agent()
    File.write!(Path.join(agent.workspace_root, "SOUL.md"), "Hydra soul")
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "worker-tool-summary"})

    results =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{id: "read-1", name: "workspace_read", arguments: %{"path" => "SOUL.md"}},
        %{id: "recall-1", name: "memory_recall", arguments: %{"query" => "hydra"}}
      ])

    assert [
             %{
               tool_name: "workspace_read",
               is_error: false,
               summary: "read SOUL.md",
               safety_classification: "workspace_read"
             },
             %{
               tool_name: "memory_recall",
               is_error: false,
               summary: "recalled 0 memories",
               safety_classification: "memory_read"
             }
           ] = results
  end

  test "channel resumes interrupted pending user turns after restart" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "webchat", title: "recoverable-chat"})

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Please recover this pending turn after restart.",
        metadata: %{"source" => "test"}
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "executing_tools",
        "latest_user_turn_id" => user_turn.id,
        "plan" => %{
          "mode" => "tool_capable",
          "steps" => [
            %{
              "id" => "provider-final",
              "kind" => "provider",
              "label" => "Recover",
              "status" => "running"
            }
          ]
        },
        "steps" => [
          %{
            "id" => "provider-final",
            "kind" => "provider",
            "label" => "Recover",
            "status" => "running"
          }
        ],
        "current_step_id" => "provider-final",
        "current_step_index" => 0,
        "resumable" => true,
        "execution_events" => []
      })

    {:ok, _channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)
    Process.sleep(100)

    refreshed = Runtime.get_conversation!(conversation.id)
    assert List.last(refreshed.turns).role == "assistant"

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "completed"
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "recovered_after_restart"))
    assert Enum.all?(channel_state.steps, &(&1["status"] == "completed"))
  end

  test "channel recovery reuses cached tool results instead of repeating side effects" do
    previous = Application.get_env(:hydra_x, :provider_request_fn)

    counter = :atomics.new(1, [])

    Application.put_env(:hydra_x, :provider_request_fn, fn _opts ->
      call_number = :atomics.add_get(counter, 1, 1)

      body =
        case call_number do
          1 ->
            %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => nil,
                    "tool_calls" => [
                      %{
                        "id" => "call-memory-1",
                        "function" => %{
                          "name" => "memory_save",
                          "arguments" =>
                            Jason.encode!(%{
                              "type" => "Fact",
                              "content" => "Remember cached tool result."
                            })
                        }
                      }
                    ]
                  },
                  "finish_reason" => "tool_calls"
                }
              ]
            }

          _ ->
            %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "Recovered without re-running the tool.",
                    "tool_calls" => nil
                  },
                  "finish_reason" => "stop"
                }
              ]
            }
        end

      {:ok, %{status: 200, body: body}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :provider_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Replay Safe Provider",
        kind: "openai_compatible",
        base_url: "https://replay-safe.test",
        api_key: "secret",
        model: "gpt-replay-safe",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "replay-safe-chat"})

    {:ok, existing_memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        conversation_id: conversation.id,
        type: "Fact",
        content: "Remember cached tool result.",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Remember cached tool result.",
        metadata: %{"source" => "test"}
      })

    fingerprint =
      ["memory_save", [{"content", "Remember cached tool result."}, {"type", "Fact"}]]
      |> :erlang.term_to_binary()
      |> Base.encode16(case: :lower)

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "interrupted",
        "latest_user_turn_id" => user_turn.id,
        "assistant_turn_id" => nil,
        "plan" => %{
          "mode" => "tool_capable",
          "steps" => [
            %{
              "id" => "tool-1-memory_save",
              "kind" => "tool",
              "name" => "memory_save",
              "status" => "completed"
            },
            %{
              "id" => "provider-final",
              "kind" => "provider",
              "label" => "Recover",
              "status" => "running"
            }
          ]
        },
        "steps" => [
          %{
            "id" => "tool-1-memory_save",
            "kind" => "tool",
            "name" => "memory_save",
            "status" => "completed"
          },
          %{
            "id" => "provider-final",
            "kind" => "provider",
            "label" => "Recover",
            "status" => "running"
          }
        ],
        "current_step_id" => "provider-final",
        "current_step_index" => 1,
        "resumable" => true,
        "tool_cache_scope_turn_id" => user_turn.id,
        "tool_cache" => [
          %{
            "fingerprint" => fingerprint,
            "tool_name" => "memory_save",
            "result" => %{
              "id" => existing_memory.id,
              "type" => existing_memory.type,
              "content" => existing_memory.content
            },
            "is_error" => false
          }
        ],
        "execution_events" => []
      })

    {:ok, _channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)
    Process.sleep(150)

    memories =
      Memory.list_memories(agent_id: agent.id)
      |> Enum.filter(&(&1.content == "Remember cached tool result."))

    assert length(memories) == 1

    refreshed = Runtime.get_conversation!(conversation.id)
    assert List.last(refreshed.turns).content =~ "Recovered without re-running the tool."

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "tool_cache_hit"))

    assert Enum.any?(
             channel_state.tool_results,
             &(&1["tool_name"] == "memory_save" and &1["cached"])
           )
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
    assert hd(recall.results).score > 0
    assert Enum.any?(hd(recall.results).reasons, &(&1 in ["lexical match", "semantic overlap"]))
  end

  test "provider and channel secrets are encrypted at rest but decrypted through runtime" do
    agent = create_agent()

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Encrypted Provider",
        kind: "openai_compatible",
        base_url: "https://encrypted-provider.test",
        api_key: "provider-secret",
        model: "gpt-encrypted",
        enabled: false
      })

    {:ok, telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "telegram-secret",
        webhook_secret: "telegram-hook",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-secret",
        webhook_secret: "discord-hook",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-secret",
        signing_secret: "slack-hook",
        enabled: true,
        default_agent_id: agent.id
      })

    raw_provider = Repo.get!(ProviderConfig, provider.id)
    raw_telegram = Repo.get!(TelegramConfig, telegram.id)
    raw_discord = Repo.get!(DiscordConfig, discord.id)
    raw_slack = Repo.get!(SlackConfig, slack.id)

    assert Secrets.encrypted?(raw_provider.api_key)
    assert Secrets.encrypted?(raw_telegram.bot_token)
    assert Secrets.encrypted?(raw_telegram.webhook_secret)
    assert Secrets.encrypted?(raw_discord.bot_token)
    assert Secrets.encrypted?(raw_discord.webhook_secret)
    assert Secrets.encrypted?(raw_slack.bot_token)
    assert Secrets.encrypted?(raw_slack.signing_secret)

    assert Runtime.get_provider_config!(provider.id).api_key == "provider-secret"
    assert Runtime.enabled_telegram_config().bot_token == "telegram-secret"
    assert Runtime.enabled_discord_config().bot_token == "discord-secret"
    assert Runtime.enabled_slack_config().bot_token == "slack-secret"

    secrets = Runtime.secret_storage_status()
    assert secrets.plaintext_records == 0
    assert secrets.encrypted_records >= 7
  end

  test "control policy defaults and agent overrides resolve through runtime" do
    agent = create_agent()
    policy = Runtime.effective_control_policy()

    assert policy.require_recent_auth_for_sensitive_actions
    assert "telegram" in policy.interactive_delivery_channels
    assert policy.ingest_roots == ["ingest"]
    assert OperatorAuth.recent_auth_window_seconds() == policy.recent_auth_window_minutes * 60

    {:ok, _override} =
      Runtime.save_agent_control_policy(agent.id, %{
        recent_auth_window_minutes: 3,
        interactive_delivery_channels_csv: "cli,webchat",
        job_delivery_channels_csv: "discord",
        ingest_roots_csv: "ingest,docs"
      })

    effective = Runtime.effective_control_policy(agent.id)
    assert effective.recent_auth_window_minutes == 3
    assert effective.interactive_delivery_channels == ["cli", "webchat"]
    assert effective.job_delivery_channels == ["discord"]
    assert effective.ingest_roots == ["ingest", "docs"]
  end

  test "hybrid memory search favors exact lexical matches over weaker semantic overlap" do
    agent = create_agent()

    {:ok, exact} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Hydra-X uses Discord delivery retries for failed notifications.",
        importance: 0.6,
        last_seen_at: DateTime.utc_now()
      })

    {:ok, semantic} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Observation",
        content: "Notification delivery on chat channels should retry when a transport fails.",
        importance: 0.9,
        last_seen_at: DateTime.utc_now()
      })

    [top | _rest] = Memory.search_ranked(agent.id, "Discord delivery retries", 5)

    assert top.entry.id == exact.id
    assert top.lexical_rank == 1

    assert semantic.id in Enum.map(
             Memory.search(agent.id, "Discord delivery retries", 5),
             & &1.id
           )
  end

  test "hybrid memory search uses provenance and type intent signals" do
    agent = create_agent()

    {:ok, ranked_goal} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Publish an operator playbook for Webchat and Discord support.",
        importance: 0.7,
        metadata: %{
          "source" => "ingest",
          "source_file" => "ops-goals.md",
          "source_section" => "webchat rollout"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _lower_match} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Observation",
        content: "Support channels should stay healthy during rollout.",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    [top | _rest] = Memory.search_ranked(agent.id, "ops webchat goal", 5)

    assert top.entry.id == ranked_goal.id
    assert "goal match" in top.reasons
    assert "source provenance" in top.reasons
    assert "ingest provenance" in top.reasons
    assert "ops" in get_in(top.entry.metadata || %{}, ["semantic_terms"])
  end

  test "hybrid memory search uses channel context signals" do
    agent = create_agent()

    {:ok, ranked_webchat} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Observation",
        content: "Retry queue needs manual triage during the current rollout.",
        importance: 0.7,
        metadata: %{"source_channel" => "webchat"},
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _discord} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Observation",
        content: "Retry queue needs manual triage during the current rollout.",
        importance: 0.7,
        metadata: %{"source_channel" => "discord"},
        last_seen_at: DateTime.utc_now()
      })

    [top | _rest] = Memory.search_ranked(agent.id, "webchat retry queue", 5)

    assert top.entry.id == ranked_webchat.id
    assert "channel context" in top.reasons
  end

  test "workspace skills can be discovered and exposed to prompts" do
    agent = create_agent()
    other_agent = create_agent()
    skill_dir = Path.join([agent.workspace_root, "skills", "deploy-checks"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "# Deploy Checks\n\nRun deployment verification steps for staged rollouts."
    )

    assert {:ok, [skill]} = Runtime.refresh_agent_skills(agent.id)
    assert skill.slug == "deploy-checks"
    assert skill.enabled

    {:ok, mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs MCP",
        transport: "stdio",
        command: "cat",
        enabled: true
      })

    assert {:ok, [binding]} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert binding.mcp_server_config_id == mcp.id
    assert binding.enabled

    prompt =
      HydraX.Agent.PromptBuilder.build(agent, [], nil, nil, %{
        tool_policy: %{},
        skill_context: Runtime.skill_prompt_context(agent.id),
        mcp_context: Runtime.mcp_prompt_context(agent.id)
      })

    system = List.first(prompt.messages)
    assert system.content =~ "## Enabled Skills"
    assert system.content =~ "Deploy Checks"
    assert system.content =~ "deployment verification steps"
    assert system.content =~ "## MCP Integrations"
    assert system.content =~ "Docs MCP"

    assert Runtime.mcp_prompt_context(other_agent.id) == ""
    Runtime.disable_agent_mcp_server!(binding.id)
    assert Runtime.mcp_prompt_context(agent.id) == ""
  end

  test "hybrid recall persists semantic vectors and exposes vector scores" do
    agent = create_agent()

    {:ok, memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Distributed worker placement should stay stable during cluster failover.",
        importance: 0.8,
        last_seen_at: DateTime.utc_now()
      })

    [top | _rest] = Memory.search_ranked(agent.id, "cluster worker placement failover", 5)

    assert top.entry.id == memory.id
    assert is_map(get_in(top.entry.metadata || %{}, ["semantic_vector"]))
    assert top.vector_score > 0.0
    assert "vector similarity" in top.reasons

    assert {:ok, %{results: [result | _]}} =
             HydraX.Tools.MemoryRecall.execute(
               %{"agent_id" => agent.id, "query" => "cluster worker placement failover"},
               %{}
             )

    assert result["vector_score"] || result[:vector_score]
  end

  test "mcp servers can be saved and probed over stdio and http" do
    {:ok, stdio} =
      Runtime.save_mcp_server(%{
        name: "Local Docs MCP",
        transport: "stdio",
        command: "cat",
        enabled: true
      })

    assert stdio.transport == "stdio"
    assert Enum.any?(Runtime.mcp_statuses(), &(&1.name == "Local Docs MCP" and &1.status == :ok))

    {:ok, http} =
      Runtime.save_mcp_server(%{
        name: "Remote MCP",
        transport: "http",
        url: "https://mcp.example.test",
        healthcheck_path: "/status",
        auth_token: "secret-token",
        enabled: true,
        retry_limit: 1
      })

    test_pid = self()

    assert {:ok, result} =
             Runtime.test_mcp_server(http,
               request_fn: fn opts ->
                 send(test_pid, {:mcp_http_probe, opts})
                 {:ok, %{status: 200}}
               end
             )

    assert result.detail =~ "HTTP 200"

    assert_receive {:mcp_http_probe, opts}
    assert opts[:url] == "https://mcp.example.test/status"
    assert {"authorization", "Bearer secret-token"} in opts[:headers]
  end

  test "workers can inspect agent MCP bindings through the MCP tool" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, mcp} =
      Runtime.save_mcp_server(%{
        name: "Healthy MCP",
        transport: "stdio",
        command: "cat",
        enabled: true
      })

    assert {:ok, [binding]} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert binding.mcp_server_config_id == mcp.id

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "mcp-tooling"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{id: "mcp-1", name: "mcp_inspect", arguments: %{"only_enabled" => true}}
      ])

    assert result.tool_name == "mcp_inspect"
    assert result.summary == "inspected 1 MCP bindings"
    assert result.safety_classification == "integration_read"
    assert length(result.result.bindings) == 1
    assert hd(result.result.bindings).name == "Healthy MCP"
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

  test "scheduled jobs can deliver run results to Discord" do
    previous = Application.get_env(:hydra_x, :discord_deliver)

    Application.put_env(:hydra_x, :discord_deliver, fn payload ->
      send(self(), {:discord_job_delivery, payload})
      {:ok, %{provider_message_id: "discord-job-1"}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :discord_deliver, previous)
      else
        Application.delete_env(:hydra_x, :discord_deliver)
      end
    end)

    agent = create_agent()

    {:ok, _discord} =
      Runtime.save_discord_config(%{
        bot_token: "discord-test-token",
        application_id: "discord-app",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Discord backup delivery",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        delivery_enabled: true,
        delivery_channel: "discord",
        delivery_target: "discord-channel"
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert_receive {:discord_job_delivery, %{external_ref: "discord-channel", content: content}}
    assert content =~ "finished with success"
    assert run.metadata["delivery"]["status"] == "delivered"
    assert run.metadata["delivery"]["metadata"]["provider_message_id"] == "discord-job-1"
  end

  test "scheduled jobs can be skipped outside active hours" do
    agent = create_agent()
    current_hour = DateTime.utc_now().hour
    start_hour = rem(current_hour + 1, 24)
    end_hour = rem(current_hour + 2, 24)

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Business Hours Review",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        active_hour_start: start_hour,
        active_hour_end: end_hour
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "skipped"
    assert run.metadata["status_reason"] == "outside_active_hours"
  end

  test "scheduled jobs retry failures and open a circuit when the threshold is hit" do
    agent = create_agent()

    blocked_root =
      Path.join(System.tmp_dir!(), "hydra-x-backup-blocked-#{System.unique_integer([:positive])}")

    File.write!(blocked_root, "not a directory")
    previous_backup_root = System.get_env("HYDRA_X_BACKUP_ROOT")
    System.put_env("HYDRA_X_BACKUP_ROOT", blocked_root)

    on_exit(fn ->
      restore_env("HYDRA_X_BACKUP_ROOT", previous_backup_root)
      File.rm_rf(blocked_root)
    end)

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Failing Backup Job",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        timeout_seconds: 3,
        retry_limit: 1,
        pause_after_failures: 1,
        cooldown_minutes: 5
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "error"
    assert run.metadata["attempt"] == 2
    assert run.metadata["retries_used"] == 1

    refreshed = Runtime.get_scheduled_job!(job.id)
    assert refreshed.circuit_state == "open"
    assert refreshed.consecutive_failures == 1
    assert refreshed.paused_until
    assert refreshed.last_failure_reason =~ "File.Error"
  end

  test "job runs can be filtered and exported" do
    agent = create_agent()

    {:ok, success_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Success Backup Job",
        kind: "backup",
        interval_minutes: 60,
        enabled: true
      })

    {:ok, skipped_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Skipped Backup Job",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        active_hour_start: rem(DateTime.utc_now().hour + 1, 24),
        active_hour_end: rem(DateTime.utc_now().hour + 2, 24)
      })

    assert {:ok, success_run} = Runtime.run_scheduled_job(success_job)
    assert success_run.status == "success"

    assert {:ok, skipped_run} = Runtime.run_scheduled_job(skipped_job)
    assert skipped_run.status == "skipped"

    success_runs = Runtime.list_job_runs(status: "success", kind: "backup", limit: 10)
    assert Enum.any?(success_runs, &(&1.id == success_run.id))
    refute Enum.any?(success_runs, &(&1.id == skipped_run.id))

    skipped_runs = Runtime.list_job_runs(search: "Skipped Backup Job", limit: 10)
    assert Enum.any?(skipped_runs, &(&1.id == skipped_run.id))

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-job-runs-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    assert {:ok, export} =
             Runtime.export_job_runs(output_root, status: "success", kind: "backup", limit: 10)

    assert File.read!(export.markdown_path) =~ "Hydra-X Job Runs"
    assert File.read!(export.markdown_path) =~ "Success Backup Job"
    assert File.read!(export.json_path) =~ "\"status\": \"success\""
  end

  test "scheduler circuits can be reset by the operator" do
    agent = create_agent()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Circuit Reset Job",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        circuit_state: "open",
        consecutive_failures: 3,
        paused_until: DateTime.add(DateTime.utc_now(), 600, :second),
        last_failure_reason: "manual test"
      })

    reset = Runtime.reset_scheduled_job_circuit!(job.id)
    assert reset.circuit_state == "closed"
    assert reset.consecutive_failures == 0
    assert reset.paused_until == nil
    assert reset.last_failure_reason == nil
  end

  test "scheduled jobs can deliver run results to Slack" do
    previous = Application.get_env(:hydra_x, :slack_deliver)

    Application.put_env(:hydra_x, :slack_deliver, fn payload ->
      send(self(), {:slack_job_delivery, payload})
      {:ok, %{provider_message_id: "slack-job-1"}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :slack_deliver, previous)
      else
        Application.delete_env(:hydra_x, :slack_deliver)
      end
    end)

    agent = create_agent()

    {:ok, _slack} =
      Runtime.save_slack_config(%{
        bot_token: "slack-test-token",
        signing_secret: "slack-signing-secret",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Slack backup delivery",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        delivery_enabled: true,
        delivery_channel: "slack",
        delivery_target: "slack-channel"
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert_receive {:slack_job_delivery, %{external_ref: "slack-channel", content: content}}
    assert content =~ "finished with success"
    assert run.metadata["delivery"]["status"] == "delivered"
    assert run.metadata["delivery"]["metadata"]["provider_message_id"] == "slack-job-1"
  end

  test "scheduled job delivery can be blocked by control policy" do
    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn _payload ->
      flunk("telegram deliver should not run when policy blocks the channel")
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    agent = create_agent()

    {:ok, _policy} =
      Runtime.save_agent_control_policy(agent.id, %{
        job_delivery_channels_csv: "discord"
      })

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Blocked Telegram Delivery",
        kind: "backup",
        interval_minutes: 60,
        enabled: true,
        delivery_enabled: true,
        delivery_channel: "telegram",
        delivery_target: "9001"
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.metadata["delivery"]["status"] == "blocked"
    assert run.metadata["delivery"]["reason"] =~ "delivery_channel_blocked_by_policy"

    [event | _] = Safety.list_events(category: "scheduler", limit: 5)
    assert event.message =~ "blocked by policy"
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

  test "scheduled jobs can be created from natural schedule text" do
    agent = create_agent()

    {:ok, weekly} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Natural Weekly Review",
        kind: "prompt",
        schedule_text: "weekly mon, fri 08:15",
        prompt: "Review weekly plan",
        enabled: true
      })

    assert weekly.schedule_mode == "weekly"
    assert weekly.weekday_csv == "mon,fri"
    assert weekly.run_hour == 8
    assert weekly.run_minute == 15
    assert Runtime.schedule_text_for(weekly) == "weekly mon,fri 08:15"

    {:ok, interval} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Natural Interval Review",
        kind: "prompt",
        schedule_text: "every 2 hours",
        prompt: "Interval review",
        enabled: true
      })

    assert interval.schedule_mode == "interval"
    assert interval.interval_minutes == 120
    assert Runtime.schedule_text_for(interval) == "every 2 hours"
  end

  test "scheduled jobs reject invalid natural schedule text and invalid weekdays" do
    agent = create_agent()

    assert {:error, changeset} =
             Runtime.save_scheduled_job(%{
               agent_id: agent.id,
               name: "Broken Natural Schedule",
               kind: "prompt",
               schedule_text: "sometimes maybe",
               enabled: true
             })

    assert "is not a supported schedule format" in errors_on(changeset).schedule_text

    assert {:error, weekly_changeset} =
             Runtime.save_scheduled_job(%{
               agent_id: agent.id,
               name: "Broken Weekly Schedule",
               kind: "prompt",
               schedule_mode: "weekly",
               weekday_csv: "maybe",
               run_hour: 8,
               run_minute: 15,
               enabled: true
             })

    assert "must use weekdays like mon,tue,wed" in errors_on(weekly_changeset).weekday_csv
  end

  test "ingest scheduled jobs import supported files from the workspace ingest directory" do
    agent = create_agent()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "ops.md"), "# Ops\n\nScheduled ingest works.")

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Workspace ingest",
        kind: "ingest",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"
    assert run.output =~ "Ingested 1 files: ops.md"
    assert run.metadata["created"] == 1
    assert run.metadata["file_count"] == 1

    assert Enum.any?(
             HydraX.Memory.list_memories(agent_id: agent.id, status: "active", limit: 20),
             &String.contains?(&1.content, "Scheduled ingest works.")
           )
  end

  test "manual ingest respects control-policy ingest roots" do
    agent = create_agent()
    docs_dir = Path.join(agent.workspace_root, "docs")
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    outside_file = Path.join(docs_dir, "ops.md")
    allowed_file = Path.join(ingest_dir, "ops.md")

    File.mkdir_p!(docs_dir)
    File.mkdir_p!(ingest_dir)
    File.write!(outside_file, "# Outside\n\nNot allowed.")
    File.write!(allowed_file, "# Allowed\n\nInside ingest root.")

    assert {:error, :ingest_path_not_allowed} = Runtime.ingest_file(agent.id, outside_file)
    assert {:ok, result} = Runtime.ingest_file(agent.id, allowed_file)
    assert result.created > 0

    {:ok, _override} =
      Runtime.save_agent_control_policy(agent.id, %{ingest_roots_csv: "ingest,docs"})

    assert {:ok, override_result} = Runtime.ingest_file(agent.id, outside_file, force: true)
    assert override_result.created > 0 or override_result.restored > 0
  end

  test "maintenance scheduled jobs refresh reports and clean up runtime state" do
    agent = create_agent()

    {:ok, old_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Old backup",
        kind: "backup",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, run} = Runtime.run_scheduled_job(old_job)

    old_timestamp =
      DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)
      |> DateTime.truncate(:microsecond)

    run
    |> Ecto.Changeset.change(inserted_at: old_timestamp)
    |> HydraX.Repo.update!()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Maintenance sweep",
        kind: "maintenance",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, maintenance_run} = Runtime.run_scheduled_job(job)
    assert maintenance_run.status == "success"
    assert maintenance_run.output =~ "Maintenance completed"
    assert maintenance_run.metadata["deleted_old_runs"] >= 1
    assert is_binary(maintenance_run.metadata["report_markdown_path"])
    assert File.exists?(maintenance_run.metadata["report_markdown_path"])
    assert File.exists?(maintenance_run.metadata["report_json_path"])
  end

  test "tool policy disables tools in the registry" do
    {:ok, _policy} =
      Runtime.save_tool_policy(%{
        shell_command_enabled: false,
        workspace_write_enabled: false,
        web_search_enabled: false
      })

    policy = Runtime.effective_tool_policy()
    schemas = HydraX.Tool.Registry.available_schemas(policy)
    tool_names = Enum.map(schemas, & &1.name)

    refute "shell_command" in tool_names
    refute "workspace_write" in tool_names
    refute "workspace_patch" in tool_names
    refute "web_search" in tool_names
    assert "memory_recall" in tool_names
    assert "http_fetch" in tool_names
    assert "workspace_list" in tool_names

    # Re-enable
    {:ok, _policy} =
      Runtime.save_tool_policy(%{
        shell_command_enabled: true,
        workspace_write_enabled: true,
        browser_automation_enabled: true,
        web_search_enabled: true
      })

    policy = Runtime.effective_tool_policy()
    schemas = HydraX.Tool.Registry.available_schemas(policy)
    tool_names = Enum.map(schemas, & &1.name)
    assert "shell_command" in tool_names
    assert "workspace_write" in tool_names
    assert "workspace_patch" in tool_names
    assert "browser_automation" in tool_names
    assert "web_search" in tool_names
  end

  test "tool policy can restrict dangerous tools by conversation channel" do
    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, _policy} =
      Runtime.save_agent_tool_policy(agent.id, %{
        "shell_command_enabled" => true,
        "shell_command_channels_csv" => "cli,control_plane",
        "browser_automation_enabled" => true,
        "browser_automation_channels_csv" => "cli",
        "workspace_write_enabled" => true,
        "workspace_write_channels_csv" => "cli"
      })

    {:ok, telegram_conversation} =
      Runtime.start_conversation(agent, %{channel: "telegram", title: "telegram-tool-policy"})

    {:ok, cli_conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "cli-tool-policy"})

    [telegram_result] =
      Worker.execute_tool_calls(agent.id, telegram_conversation, [
        %{id: "shell-1", name: "shell_command", arguments: %{command: "pwd"}}
      ])

    assert telegram_result.is_error
    assert telegram_result.result.error =~ "disabled by policy"

    [browser_blocked] =
      Worker.execute_tool_calls(agent.id, telegram_conversation, [
        %{
          id: "browser-1",
          name: "browser_automation",
          arguments: %{action: "fetch_page", url: "https://example.com"}
        }
      ])

    assert browser_blocked.is_error
    assert browser_blocked.result.error =~ "disabled by policy"

    [cli_result] =
      Worker.execute_tool_calls(agent.id, cli_conversation, [
        %{id: "shell-2", name: "shell_command", arguments: %{command: "pwd"}}
      ])

    refute cli_result.is_error
    assert cli_result.result.output =~ agent.workspace_root
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

      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => "OK"}, "finish_reason" => "stop"}]}
       }}
    end

    assert {:ok, %{content: "OK", provider: "OpenAI Test"}} =
             Runtime.test_provider_config(provider, request_fn: request_fn)
  end

  test "router falls back through an agent provider route" do
    previous = Application.get_env(:hydra_x, :provider_request_fn)

    Application.put_env(:hydra_x, :provider_request_fn, fn opts ->
      case opts[:url] do
        "https://broken-route.test/v1/chat/completions" ->
          {:error, :econnrefused}

        "https://healthy-route.test/v1/chat/completions" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "choices" => [
                 %{
                   "message" => %{"content" => "Fallback route worked", "tool_calls" => nil},
                   "finish_reason" => "stop"
                 }
               ]
             }
           }}
      end
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :provider_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()

    {:ok, primary} =
      Runtime.save_provider_config(%{
        name: "Broken Route",
        kind: "openai_compatible",
        base_url: "https://broken-route.test",
        api_key: "secret",
        model: "gpt-broken",
        enabled: false
      })

    {:ok, fallback} =
      Runtime.save_provider_config(%{
        name: "Healthy Route",
        kind: "openai_compatible",
        base_url: "https://healthy-route.test",
        api_key: "secret",
        model: "gpt-healthy",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => primary.id,
        "fallback_provider_ids_csv" => Integer.to_string(fallback.id)
      })

    assert {:ok, %{content: "Fallback route worked", provider: "Healthy Route"}} =
             HydraX.LLM.Router.complete(%{
               messages: [%{role: "user", content: "hello"}],
               agent_id: agent.id,
               process_type: "channel"
             })
  end

  test "warming an agent provider route updates runtime readiness" do
    previous = Application.get_env(:hydra_x, :provider_test_request_fn)

    Application.put_env(:hydra_x, :provider_test_request_fn, fn _opts ->
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
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :provider_test_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :provider_test_request_fn)
      end
    end)

    agent = create_agent()

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Warm Provider",
        kind: "openai_compatible",
        base_url: "https://warm-route.test",
        api_key: "secret",
        model: "gpt-warm",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, _updated, status} = Runtime.warm_agent_provider_routing(agent.id)
    assert status["status"] == "ready"
    assert status["selected_provider_id"] == provider.id

    runtime = Runtime.agent_runtime_status(agent.id)
    assert runtime.warmup_status == "ready"
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

    {:ok, _goal} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Keep Webchat rollout healthy."
      })

    {:ok, _decision} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Use Discord as the fallback operator channel."
      })

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Hydra-X keeps a typed graph memory."
      })

    {:ok, _channel_memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Observation",
        content: "Webchat retries need continued operator monitoring.",
        metadata: %{"source_channel" => "webchat"}
      })

    bulletin = Runtime.refresh_agent_bulletin!(agent.id)

    assert bulletin.memory_count >= 1
    assert bulletin.content =~ "## Active Goals And Todos"
    assert bulletin.content =~ "## Current Decisions And Preferences"
    assert bulletin.content =~ "## Channel-Specific Context"
    assert bulletin.content =~ "## Relevant Context"
    assert bulletin.content =~ "Keep Webchat rollout healthy."
    assert bulletin.content =~ "Use Discord as the fallback operator channel."
    assert bulletin.content =~ "[Observation/webchat] Webchat retries need continued operator monitoring."
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
