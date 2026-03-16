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

    assert Enum.any?(channel_state.steps, fn step ->
             step["kind"] == "provider" and not is_nil(step["summary"]) and
               step["attempt_count"] == 1 and not is_nil(step["started_at"]) and
               not is_nil(step["completed_at"]) and step["owner"] == "channel" and
               step["lifecycle"] == "completed" and step["result_source"] == "fresh" and
               step["retry_state"]["attempt_count"] == 1 and
               step["retry_state"]["last_status"] == "completed" and
               length(step["attempt_history"] || []) == 2
           end)

    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "provider_requested"))
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "provider_completed"))

    assert Enum.any?(channel_state.execution_events, fn event ->
             event["phase"] == "provider_completed" and
               event["details"]["kind"] == "provider" and
               event["details"]["name"] == "response_generation" and
               event["details"]["lifecycle"] == "completed" and
               event["details"]["result_source"] == "fresh"
           end)
  end

  test "planner captures enabled skill hints from workspace metadata" do
    agent = create_agent()
    skill_dir = Path.join([agent.workspace_root, "skills", "deploy-checks"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Deploy Checks\nsummary: Run deployment verification steps for staged rollouts.\nversion: 1.2.0\ntags: deploy,release,checks\ntools: shell_command,web_search\nchannels: cli,slack\nrequires: release-window\n---\n# Deploy Checks\n\nRun deployment verification steps for staged rollouts."
    )

    assert {:ok, _skills} = Runtime.refresh_agent_skills(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "skill-hints"})

    _response =
      Channel.submit(
        agent,
        conversation,
        "Run the deploy checks before release.",
        %{source: "test"}
      )

    channel_state = Runtime.conversation_channel_state(conversation.id)
    [hint | _] = channel_state.plan["skill_hints"]
    [skill_step | _] = channel_state.steps

    assert hint["slug"] == "deploy-checks"
    assert hint["reason"] =~ "deploy"
    assert skill_step["kind"] == "skill"
    assert skill_step["status"] == "completed"
    assert skill_step["summary"] =~ "Matched 1 skill hints"
    assert skill_step["result_source"] == "plan"
    assert skill_step["retry_state"]["attempt_count"] == 1
    assert skill_step["retry_state"]["last_status"] == "completed"
    assert length(skill_step["attempt_history"] || []) == 2
  end

  test "planner emits typed integration and memory steps" do
    conversation = %{channel: "cli"}

    tools = [
      %{name: "mcp_invoke", description: "Invoke integrations"},
      %{name: "mcp_probe", description: "Probe integrations"},
      %{name: "memory_recall", description: "Recall memories"},
      %{name: "shell_command", description: "Run shell commands"}
    ]

    plan =
      HydraX.Agent.Planner.build(
        conversation,
        [
          %{id: 1, content: "Call MCP to probe the integration health and remember what you know"}
        ],
        tools,
        []
      )

    assert Enum.any?(plan["steps"], &(&1["name"] == "mcp_invoke" and &1["kind"] == "integration"))
    assert Enum.any?(plan["steps"], &(&1["name"] == "mcp_probe" and &1["kind"] == "integration"))
    assert Enum.any?(plan["steps"], &(&1["name"] == "memory_recall" and &1["kind"] == "memory"))
    refute Enum.any?(plan["steps"], &(&1["name"] == "shell_command"))
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

  test "worker can inspect enabled skills with tags" do
    agent = create_agent()
    skill_dir = Path.join([agent.workspace_root, "skills", "deploy-checks"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Deploy Checks\nsummary: Run deployment verification steps for staged rollouts.\nversion: 1.2.0\ntags: deploy,release,checks\ntools: shell_command,web_search\nchannels: cli,slack\nrequires: release-window\n---\n# Deploy Checks\n\nRun deployment verification steps for staged rollouts."
    )

    assert {:ok, _skills} = Runtime.refresh_agent_skills(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "skill-inspect"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{id: "skill-1", name: "skill_inspect", arguments: %{"tag" => "deploy"}}
      ])

    refute result.is_error
    assert result.summary == "inspected 1 skills"
    [skill] = result.result.skills
    assert skill.slug == "deploy-checks"
    assert skill.tags == ["deploy", "release", "checks"]
    assert skill.version == "1.2.0"
    assert skill.tools == ["shell_command", "web_search"]
    assert skill.channels == ["cli", "slack"]
    assert skill.requires == ["release-window"]
    assert skill.advisory_requirements == ["release-window"]
    assert skill.manifest_valid
    assert skill.validation_errors == []
  end

  test "channel ownership is persisted for postgres-backed coordination" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "ownership-chat"})

    response =
      Channel.submit(
        agent,
        conversation,
        "Tell me who owns this conversation.",
        %{source: "test"}
      )

    assert response =~ "Mock response"

    refreshed = Runtime.get_conversation!(conversation.id)
    channel_state = Runtime.conversation_channel_state(conversation.id)
    ownership = refreshed.metadata["ownership"]

    assert ownership["mode"] == "database_lease"
    assert ownership["lease_name"] == "conversation:#{conversation.id}"
    assert ownership["owner"] == channel_state.ownership["owner"]
    assert ownership["stage"] == "idle"
    assert channel_state.ownership["mode"] == "database_lease"
    assert Runtime.active_lease("conversation:#{conversation.id}")
  end

  test "channel heartbeat renews the active conversation lease" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "ownership-heartbeat"})

    {:ok, channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    initial_lease = Runtime.active_lease("conversation:#{conversation.id}")
    assert initial_lease.owner == Runtime.coordination_status().owner

    send(channel_pid, :lease_tick)

    wait_for(fn ->
      refreshed_lease = Runtime.active_lease("conversation:#{conversation.id}")
      DateTime.compare(refreshed_lease.expires_at, initial_lease.expires_at) == :gt
    end)

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["ownership"]["owner"] == Runtime.coordination_status().owner
    assert refreshed.metadata["ownership"]["stage"] == "idle"
  end

  test "channel submit defers to remote ownership and persists the pending user turn" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "ownership-deferred"})

    wait_for(
      fn ->
        match?(
          {:ok, _lease},
          Runtime.claim_lease("conversation:#{conversation.id}",
            owner: "node:remote",
            ttl_seconds: 60
          )
        )
      end,
      80
    )

    assert {:deferred, reason} =
             Channel.submit(
               agent,
               conversation,
               "Hold this for the owning node.",
               %{source: "test"}
             )

    assert reason =~ "node:remote"

    [turn] = Runtime.list_turns(conversation.id)
    assert turn.role == "user"
    assert turn.content == "Hold this for the owning node."
    assert turn.metadata["deferred_to_owner"] == "node:remote"

    wait_for(
      fn ->
        channel_state = Runtime.conversation_channel_state(conversation.id)
        channel_state.status == "deferred"
      end,
      240
    )

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "deferred"
    assert channel_state.resumable
    assert channel_state.pending_turn_id == turn.id
    assert channel_state.ownership["owner"] == "node:remote"
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "ownership_deferred"))
  end

  test "running channel defers and stops when it loses the conversation lease" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "ownership-loss"})

    {:ok, channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    task =
      Task.async(fn ->
        Channel.submit(
          agent,
          conversation,
          "Lose this lease before processing.",
          %{source: "test"}
        )
      end)

    wait_for(fn ->
      Runtime.list_turns(conversation.id) |> length() == 1
    end)

    stale_lease = Runtime.get_lease("conversation:#{conversation.id}")

    stale_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    wait_for(
      fn ->
        match?(
          {:ok, _lease},
          Runtime.claim_lease("conversation:#{conversation.id}",
            owner: "node:remote",
            ttl_seconds: 60
          )
        )
      end,
      240
    )

    send(channel_pid, :lease_tick)

    assert {:deferred, reason} = Task.await(task, 5_000)
    assert reason =~ "node:remote"

    wait_for(fn -> not Process.alive?(channel_pid) end)

    wait_for(
      fn -> Runtime.conversation_channel_state(conversation.id).status == "deferred" end,
      240
    )

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "deferred"
    assert channel_state.resumable
    assert channel_state.ownership["owner"] == "node:remote"
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "ownership_lost"))
    refute Enum.any?(Runtime.list_turns(conversation.id), &(&1.role == "assistant"))
  end

  test "final provider responses survive ownership handoff without a second provider call" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    previous_request_fn = Application.get_env(:hydra_x, :provider_request_fn)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    counter = :atomics.new(1, [])
    test_pid = self()

    Application.put_env(:hydra_x, :provider_request_fn, fn _opts ->
      :atomics.add_get(counter, 1, 1)
      send(test_pid, :provider_response_requested)
      Process.sleep(200)

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" => "Captured before ownership handoff.",
                 "tool_calls" => nil
               },
               "finish_reason" => "stop"
             }
           ]
         }
       }}
    end)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_request_fn do
        Application.put_env(:hydra_x, :provider_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Handoff Safe Provider",
        kind: "openai_compatible",
        base_url: "https://handoff-safe.test",
        api_key: "secret",
        model: "gpt-handoff-safe",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "provider-handoff-cache"})

    {:ok, channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)
    on_exit(fn -> if Process.alive?(channel_pid), do: shutdown_process(channel_pid) end)

    task =
      Task.async(fn ->
        Channel.submit(
          agent,
          conversation,
          "Hold the completed provider response for the new owner.",
          %{source: "test"}
        )
      end)

    assert_receive :provider_response_requested, 1_000

    stale_lease = Runtime.get_lease("conversation:#{conversation.id}")

    stale_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    wait_for(fn ->
      match?(
        {:ok, _lease},
        Runtime.claim_lease("conversation:#{conversation.id}",
          owner: "node:remote",
          ttl_seconds: 60
        )
      )
    end)

    assert {:deferred, reason} = Task.await(task, 5_000)
    assert reason =~ "node:remote"

    wait_for(fn -> not Process.alive?(channel_pid) end)

    wait_for(
      fn ->
        channel_state = Runtime.conversation_channel_state(conversation.id)

        channel_state.status in ["deferred", "interrupted"] and
          get_in(channel_state.pending_response || %{}, ["content"]) ==
            "Captured before ownership handoff."
      end,
      240
    )

    wait_for(
      fn ->
        channel_state = Runtime.conversation_channel_state(conversation.id)

        not Process.alive?(channel_pid) and
          channel_state.status in ["deferred", "interrupted"]
      end,
      240
    )

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status in ["deferred", "interrupted"]
    assert channel_state.pending_response["content"] == "Captured before ownership handoff."
    assert channel_state.pending_response["metadata"]["provider"] == "Handoff Safe Provider"
    assert :atomics.get(counter, 1) == 1
    refute Enum.any?(Runtime.list_turns(conversation.id), &(&1.role == "assistant"))

    remote_lease = Runtime.get_lease("conversation:#{conversation.id}")

    remote_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    wait_for(fn ->
      match?(
        {:ok, _lease},
        Runtime.claim_lease("conversation:#{conversation.id}", ttl_seconds: 60)
      )
    end)

    {:ok, resumed_channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    on_exit(fn ->
      if Process.alive?(resumed_channel_pid), do: shutdown_process(resumed_channel_pid)
    end)

    wait_for(
      fn ->
        Runtime.list_turns(conversation.id)
        |> Enum.any?(
          &(&1.role == "assistant" and &1.content == "Captured before ownership handoff.")
        )
      end,
      400
    )

    final_state = Runtime.conversation_channel_state(conversation.id)
    assert final_state.status == "completed"
    assert final_state.pending_response == nil
    assert Enum.any?(final_state.execution_events, &(&1["phase"] == "handoff_response_replayed"))
    assert :atomics.get(counter, 1) == 1

    assert Enum.any?(final_state.execution_events, fn event ->
             event["phase"] == "handoff_response_replayed" and
               event["details"]["kind"] == "provider" and
               event["details"]["name"] == "response_generation" and
               event["details"]["lifecycle"] == "replayed" and
               event["details"]["result_source"] == "handoff_replay" and
               event["details"]["replayed"] == true
           end)

    assert Enum.any?(final_state.steps, fn step ->
             step["kind"] == "provider" and step["lifecycle"] == "replayed" and
               step["result_source"] == "handoff_replay" and step["replayed"] and
               step["replay_count"] == 1 and
               step["retry_state"]["last_status"] == "replayed" and
               step["retry_state"]["result_source"] == "handoff_replay"
           end)
  end

  test "tool results are cached across ownership handoff so side effects are not repeated" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    previous_request_fn = Application.get_env(:hydra_x, :provider_request_fn)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    counter = :atomics.new(1, [])
    test_pid = self()

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_request_fn do
        Application.put_env(:hydra_x, :provider_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()
    marker_path = Path.join(agent.workspace_root, "tool-started.txt")
    log_path = Path.join(agent.workspace_root, "tool-executions.log")

    command =
      "sh -c \"echo started > #{marker_path} && echo tool-run >> #{log_path} && sleep 1 && echo done\""

    Application.put_env(:hydra_x, :provider_request_fn, fn _opts ->
      call_number = :atomics.add_get(counter, 1, 1)

      body =
        case call_number do
          number when number in [1, 2] ->
            send(test_pid, {:tool_round_requested, call_number})

            %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => nil,
                    "tool_calls" => [
                      %{
                        "id" => "call-shell-1",
                        "function" => %{
                          "name" => "shell_command",
                          "arguments" => Jason.encode!(%{"command" => command})
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
                    "content" => "Recovered via cached tool result.",
                    "tool_calls" => nil
                  },
                  "finish_reason" => "stop"
                }
              ]
            }
        end

      {:ok, %{status: 200, body: body}}
    end)

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Tool Handoff Provider",
        kind: "openai_compatible",
        base_url: "https://tool-handoff.test",
        api_key: "secret",
        model: "gpt-tool-handoff",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, _policy} =
      Runtime.save_agent_tool_policy(agent.id, %{
        "shell_command_enabled" => true,
        "shell_command_channels_csv" => "cli",
        "shell_allowlist_csv" => "sh"
      })

    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "tool-handoff-cache"})

    {:ok, channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)
    on_exit(fn -> if Process.alive?(channel_pid), do: shutdown_process(channel_pid) end)

    task =
      Task.async(fn ->
        Channel.submit(
          agent,
          conversation,
          "Run the tool, then hand off the conversation safely.",
          %{source: "test"}
        )
      end)

    assert_receive {:tool_round_requested, 1}, 1_000
    wait_for(fn -> File.exists?(marker_path) end, 80)

    stale_lease = Runtime.get_lease("conversation:#{conversation.id}")

    stale_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}",
               owner: "node:remote",
               ttl_seconds: 60
             )

    send(channel_pid, :lease_tick)

    wait_for(
      fn ->
        handoff = Runtime.conversation_channel_state(conversation.id).handoff || %{}
        handoff["status"] == "pending" and handoff["waiting_for"] == "tool_results"
      end,
      80
    )

    assert Process.alive?(channel_pid)

    assert {:deferred, reason} = Task.await(task, 5_000)
    assert reason =~ "node:remote"

    wait_for(fn -> not Process.alive?(channel_pid) end)

    wait_for(
      fn -> Runtime.conversation_channel_state(conversation.id).status == "deferred" end,
      240
    )

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "deferred"
    assert channel_state.handoff == nil
    assert length(channel_state.tool_cache || []) == 1
    assert Enum.any?(channel_state.tool_results || [], &(&1["tool_name"] == "shell_command"))
    assert File.read!(log_path) == "tool-run\n"

    remote_lease = Runtime.get_lease("conversation:#{conversation.id}")

    remote_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}", ttl_seconds: 60)

    {:ok, resumed_channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    on_exit(fn ->
      if Process.alive?(resumed_channel_pid), do: shutdown_process(resumed_channel_pid)
    end)

    assert_receive {:tool_round_requested, 2}, 1_000

    wait_for(
      fn ->
        Runtime.list_turns(conversation.id)
        |> Enum.any?(
          &(&1.role == "assistant" and &1.content == "Recovered via cached tool result.")
        )
      end,
      120
    )

    final_state = Runtime.conversation_channel_state(conversation.id)
    assert final_state.status == "completed"
    assert Enum.any?(final_state.execution_events, &(&1["phase"] == "tool_cache_hit"))

    assert Enum.any?(final_state.execution_events, fn event ->
             event["phase"] == "tool_cache_hit" and
               event["details"]["kind"] == "tool" and
               event["details"]["name"] == "cache_reuse" and
               event["details"]["lifecycle"] == "cached" and
               event["details"]["result_source"] == "cache"
           end)

    assert File.read!(log_path) == "tool-run\n"
    assert :atomics.get(counter, 1) == 3
  end

  test "unfinished handoff work can be resumed after the original channel process dies" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    previous_request_fn = Application.get_env(:hydra_x, :provider_request_fn)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    counter = :atomics.new(1, [])
    test_pid = self()

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_request_fn do
        Application.put_env(:hydra_x, :provider_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()
    marker_path = Path.join(agent.workspace_root, "restartable-tool-started.txt")
    command = "sh -c \"echo started > #{marker_path} && sleep 2 && echo ready\""

    Application.put_env(:hydra_x, :provider_request_fn, fn _opts ->
      call_number = :atomics.add_get(counter, 1, 1)

      body =
        case call_number do
          number when number in [1, 2] ->
            send(test_pid, {:restartable_tool_round_requested, call_number})

            %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => nil,
                    "tool_calls" => [
                      %{
                        "id" => "call-shell-restart",
                        "function" => %{
                          "name" => "shell_command",
                          "arguments" => Jason.encode!(%{"command" => command})
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
                    "content" => "Recovered after the original channel died.",
                    "tool_calls" => nil
                  },
                  "finish_reason" => "stop"
                }
              ]
            }
        end

      {:ok, %{status: 200, body: body}}
    end)

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Restartable Handoff Provider",
        kind: "openai_compatible",
        base_url: "https://restartable-handoff.test",
        api_key: "secret",
        model: "gpt-restartable-handoff",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, _policy} =
      Runtime.save_agent_tool_policy(agent.id, %{
        "shell_command_enabled" => true,
        "shell_command_channels_csv" => "cli",
        "shell_allowlist_csv" => "sh"
      })

    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "handoff-restart-after-crash"})

    {:ok, channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    task =
      Task.Supervisor.async_nolink(HydraX.TaskSupervisor, fn ->
        Channel.submit(
          agent,
          conversation,
          "Resume this after the original channel disappears.",
          %{source: "test"}
        )
      end)

    assert_receive {:restartable_tool_round_requested, 1}, 1_000
    wait_for(fn -> File.exists?(marker_path) end, 80)

    stale_lease = Runtime.get_lease("conversation:#{conversation.id}")

    stale_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}",
               owner: "node:remote",
               ttl_seconds: 60
             )

    send(channel_pid, :lease_tick)

    wait_for(
      fn ->
        handoff = Runtime.conversation_channel_state(conversation.id).handoff || %{}
        state = Runtime.conversation_channel_state(conversation.id)
        state.status == "deferred" and handoff["waiting_for"] == "tool_results"
      end,
      80
    )

    shutdown_process(channel_pid)
    wait_for(fn -> not Process.alive?(channel_pid) end)

    assert catch_exit(Task.await(task, 5_000))

    remote_lease = Runtime.get_lease("conversation:#{conversation.id}")

    remote_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}", ttl_seconds: 60)

    {:ok, resumed_channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    on_exit(fn ->
      if Process.alive?(resumed_channel_pid), do: shutdown_process(resumed_channel_pid)
    end)

    assert_receive {:restartable_tool_round_requested, 2}, 1_000

    wait_for(
      fn ->
        Runtime.list_turns(conversation.id)
        |> Enum.any?(
          &(&1.role == "assistant" and &1.content == "Recovered after the original channel died.")
        )
      end,
      120
    )

    final_state = Runtime.conversation_channel_state(conversation.id)
    assert final_state.status == "completed"
    assert final_state.handoff == nil
    assert Enum.any?(final_state.execution_events, &(&1["phase"] == "handoff_restart"))
  end

  test "restarted channels clear partial stream capture after unfinished stream handoff" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    previous_request_fn = Application.get_env(:hydra_x, :provider_request_fn)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_request_fn do
        Application.put_env(:hydra_x, :provider_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()

    Application.put_env(:hydra_x, :provider_request_fn, fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" => "Recovered after restarting the interrupted stream.",
                 "tool_calls" => nil
               },
               "finish_reason" => "stop"
             }
           ]
         }
       }}
    end)

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Restartable Stream Provider",
        kind: "openai_compatible",
        base_url: "https://restartable-stream.test",
        api_key: "secret",
        model: "gpt-restartable-stream",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "restart-after-stream-handoff"})

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Finish the interrupted stream after restarting.",
        metadata: %{"source" => "test"}
      })

    current_owner = Runtime.coordination_status().owner

    assert {:ok, _lease} =
             Runtime.claim_lease("conversation:#{conversation.id}", ttl_seconds: 60)

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "deferred",
        "resumable" => true,
        "pending_turn_id" => user_turn.id,
        "handoff" => %{
          "status" => "pending",
          "waiting_for" => "stream_response",
          "owner" => current_owner,
          "owner_node" => "nonode@nohost"
        },
        "stream_capture" => %{
          "content" => "Partial streamed reply",
          "chunk_count" => 2,
          "provider" => "Restartable Stream Provider"
        },
        "ownership" => %{
          "mode" => "database_lease",
          "lease_name" => "conversation:#{conversation.id}",
          "owner" => current_owner,
          "owner_node" => "nonode@nohost",
          "stage" => "deferred"
        },
        "execution_events" => []
      })

    initial_state = Runtime.conversation_channel_state(conversation.id)
    assert initial_state.stream_capture["content"] == "Partial streamed reply"
    assert initial_state.handoff["waiting_for"] == "stream_response"

    {:ok, channel_pid} = HydraX.Agent.Channel.ensure_started(agent.id, conversation)

    on_exit(fn ->
      if Process.alive?(channel_pid), do: shutdown_process(channel_pid)
    end)

    wait_for(
      fn ->
        Runtime.list_turns(conversation.id)
        |> Enum.any?(
          &(&1.role == "assistant" and
              &1.content == "Recovered after restarting the interrupted stream.")
        )
      end,
      120
    )

    final_state = Runtime.conversation_channel_state(conversation.id)
    assert final_state.status == "completed"
    assert final_state.handoff == nil
    assert final_state.stream_capture == nil

    assert Enum.any?(final_state.execution_events, fn event ->
             event["phase"] == "handoff_restart" and
               event["details"]["waiting_for"] == "stream_response" and
               event["details"]["captured_chars"] > 0
           end)
  end

  test "owned deferred conversations can be resumed through the runtime" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "webchat", title: "owned-deferred-runtime"})

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Resume this from the ownership handoff queue.",
        metadata: %{"source" => "test"}
      })

    current_owner = Runtime.coordination_status().owner

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "deferred",
        "resumable" => true,
        "pending_turn_id" => user_turn.id,
        "ownership" => %{
          "mode" => "database_lease",
          "lease_name" => "conversation:#{conversation.id}",
          "owner" => current_owner,
          "owner_node" => "nonode@nohost",
          "stage" => "deferred"
        },
        "execution_events" => []
      })

    summary = Runtime.resume_owned_conversations()

    assert summary.resumed_count == 1
    assert [%{conversation_id: conversation_id, status: "resumed"}] = summary.results
    assert conversation_id == conversation.id

    Process.sleep(100)

    refreshed = Runtime.get_conversation!(conversation.id)
    assert List.last(refreshed.turns).role == "assistant"

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "completed"
    assert channel_state.recovery_lineage["turn_scope_id"] == user_turn.id
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "recovered_after_restart"))
  end

  test "runtime can take over expired deferred conversation ownership" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "webchat", title: "expired-deferred-runtime"})

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Take over this expired deferred conversation.",
        metadata: %{"source" => "test"}
      })

    assert {:ok, stale_lease} =
             Runtime.claim_lease("conversation:#{conversation.id}",
               owner: "node:stale",
               ttl_seconds: 60
             )

    stale_lease
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "deferred",
        "resumable" => true,
        "pending_turn_id" => user_turn.id,
        "ownership" => %{
          "mode" => "database_lease",
          "lease_name" => "conversation:#{conversation.id}",
          "owner" => "node:stale",
          "owner_node" => "stale@node",
          "stage" => "deferred"
        },
        "execution_events" => []
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "ownership" => %{
          "mode" => "database_lease",
          "lease_name" => "conversation:#{conversation.id}",
          "owner" => "node:stale",
          "owner_node" => "stale@node",
          "stage" => "deferred"
        }
      })

    summary = Runtime.resume_owned_conversations()

    assert summary.resumed_count == 1
    Process.sleep(100)

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["ownership"]["owner"] == Runtime.coordination_status().owner
    assert List.last(refreshed.turns).role == "assistant"
  end

  test "runtime resumes stale streaming conversations from checkpoint state" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "webchat", title: "stale-stream-runtime"})

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Recover this stale streamed conversation.",
        metadata: %{"source" => "test"}
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "resumable" => true,
        "pending_turn_id" => user_turn.id,
        "ownership" => %{
          "mode" => "database_lease",
          "lease_name" => "conversation:#{conversation.id}",
          "owner" => Runtime.coordination_status().owner,
          "owner_node" => "nonode@nohost",
          "stage" => "streaming"
        },
        "stream_capture" => %{
          "content" => "Partial streamed answer before restart.",
          "chunk_count" => 2,
          "provider" => "mock"
        },
        "updated_at" => DateTime.add(DateTime.utc_now(), -120, :second),
        "execution_events" => []
      })

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.resume_stage == "streaming"
    assert channel_state.stale_stream

    summary = Runtime.resume_owned_conversations()

    assert summary.resumed_count == 1

    assert [%{conversation_id: conversation_id, status: "resumed", resume_from: "streaming"}] =
             summary.results

    assert conversation_id == conversation.id

    Process.sleep(100)

    refreshed = Runtime.get_conversation!(conversation.id)
    assert List.last(refreshed.turns).role == "assistant"

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "completed"
    refute channel_state.stale_stream
    assert Enum.any?(channel_state.execution_events, &(&1["phase"] == "recovered_after_restart"))
  end

  test "scheduler poll resumes owned deferred conversations" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)
    previous_deliver = Application.get_env(:hydra_x, :telegram_deliver)

    test_pid = self()

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(test_pid, {:scheduler_deferred_delivery, payload})
      {:ok, %{provider_message_id: "scheduler-telegram-1"}}
    end)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_deliver do
        Application.put_env(:hydra_x, :telegram_deliver, previous_deliver)
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

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        external_ref: "7171",
        title: "owned-deferred-scheduler"
      })

    {:ok, user_turn} =
      Runtime.append_turn(conversation, %{
        role: "user",
        kind: "message",
        content: "Let the scheduler pick this up.",
        metadata: %{"source" => "test"}
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "deferred",
        "resumable" => true,
        "pending_turn_id" => user_turn.id,
        "ownership" => %{
          "mode" => "database_lease",
          "lease_name" => "conversation:#{conversation.id}",
          "owner" => Runtime.coordination_status().owner,
          "owner_node" => "nonode@nohost",
          "stage" => "deferred"
        },
        "latest_user_turn_id" => user_turn.id,
        "execution_events" => []
      })

    {:ok, _conversation} =
      Runtime.update_conversation_metadata(conversation, %{
        "ownership" => %{
          "mode" => "database_lease",
          "owner" => Runtime.coordination_status().owner,
          "owner_node" => "nonode@nohost",
          "stage" => "deferred"
        },
        "last_delivery" => %{
          "channel" => "telegram",
          "status" => "deferred",
          "external_ref" => "7171",
          "reply_context" => %{"reply_to_message_id" => 808},
          "metadata" => %{"ownership_deferred" => true}
        }
      })

    scheduler_pid =
      Process.whereis(HydraX.Scheduler) || start_supervised!({HydraX.Scheduler, %{}})

    if lease = Runtime.get_lease("scheduler:poller") do
      lease
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      |> Repo.update!()
    end

    send(scheduler_pid, :poll)

    wait_for(
      fn ->
        Runtime.get_conversation!(conversation.id).turns
        |> List.last()
        |> then(&(&1 && &1.role == "assistant"))
      end,
      80
    )

    refreshed = Runtime.get_conversation!(conversation.id)
    assert List.last(refreshed.turns).role == "assistant"

    assert_receive {:scheduler_deferred_delivery,
                    %{chat_id: "7171", reply_to_message_id: 808, text: delivered_text}}

    assert delivered_text =~ "Let the scheduler pick this up."

    wait_for(
      fn ->
        Runtime.get_conversation!(conversation.id).metadata["last_delivery"]["status"] ==
          "delivered"
      end,
      80
    )

    channel_state = Runtime.conversation_channel_state(conversation.id)
    assert channel_state.status == "completed"
    assert channel_state.recovery_lineage["turn_scope_id"] == user_turn.id

    refreshed = Runtime.get_conversation!(conversation.id)
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
  end

  test "scheduler poll processes owned queued ingress messages" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    previous_deliver = Application.get_env(:hydra_x, :telegram_deliver)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    test_pid = self()

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(test_pid, {:scheduler_ingress_delivery, payload})
      {:ok, %{provider_message_id: "scheduler-ingress-1"}}
    end)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end

      if previous_deliver do
        Application.put_env(:hydra_x, :telegram_deliver, previous_deliver)
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

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "telegram",
        external_ref: "8181",
        title: "queued-ingress-scheduler"
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "ingress", %{
        "status" => "queued",
        "channel" => "telegram",
        "external_ref" => "8181",
        "owner" => Runtime.coordination_status().owner,
        "owner_node" => "nonode@nohost",
        "lease_name" => "ingress:telegram:8181",
        "message_count" => 1,
        "messages" => [
          %{
            "channel" => "telegram",
            "external_ref" => "8181",
            "content" => "Let the scheduler process queued ingress.",
            "metadata" => %{"reply_to_message_id" => 828}
          }
        ]
      })

    scheduler_pid =
      Process.whereis(HydraX.Scheduler) || start_supervised!({HydraX.Scheduler, %{}})

    if lease = Runtime.get_lease("scheduler:poller") do
      lease
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      |> Repo.update!()
    end

    send(scheduler_pid, :poll)

    wait_for(
      fn ->
        checkpoint = Runtime.get_checkpoint(conversation.id, "ingress")
        checkpoint && checkpoint.state["message_count"] == 0
      end,
      80
    )

    assert_receive {:scheduler_ingress_delivery,
                    %{chat_id: "8181", reply_to_message_id: 828, text: delivered_text}}

    assert delivered_text =~ "Let the scheduler process queued ingress."

    refreshed = Runtime.get_conversation!(conversation.id)
    assert length(refreshed.turns) == 2
    assert refreshed.metadata["last_delivery"]["status"] == "delivered"
    assert Runtime.get_checkpoint(conversation.id, "ingress").state["message_count"] == 0
  end

  test "skill prompt context excludes invalid manifests and unsatisfied explicit requirements" do
    agent = create_agent()

    invalid_dir = Path.join([agent.workspace_root, "skills", "invalid-skill"])
    File.mkdir_p!(invalid_dir)

    File.write!(
      Path.join(invalid_dir, "SKILL.md"),
      "---\nname: Invalid Skill\nsummary: Broken frontmatter.\ntools: shell_command,unknown_tool\nchannels: cli,unknown_channel\nrequires: env:\n---\n# Invalid Skill\n\nShould not load into prompt context."
    )

    gated_dir = Path.join([agent.workspace_root, "skills", "release-gated"])
    File.mkdir_p!(gated_dir)

    File.write!(
      Path.join(gated_dir, "SKILL.md"),
      "---\nname: Release Gated\nsummary: Only active when explicit requirements are met.\ntools: shell_command\nchannels: cli\nrequires: env:HYDRA_X_RELEASE_WINDOW,mcp:docs-http\n---\n# Release Gated\n\nRuns only when release window and docs MCP are available."
    )

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs HTTP MCP",
        transport: "http",
        url: "https://mcp.example.test",
        metadata: %{"slug" => "docs-http"},
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert {:ok, _skills} = Runtime.refresh_agent_skills(agent.id)

    skills = Runtime.list_skills(agent_id: agent.id)
    invalid = Enum.find(skills, &(&1.slug == "invalid-skill"))
    gated = Enum.find(skills, &(&1.slug == "release-gated"))

    refute is_nil(invalid)
    refute is_nil(gated)

    refute get_in(invalid.metadata, ["manifest_valid"])
    assert "unknown tool unknown_tool" in get_in(invalid.metadata, ["validation_errors"])
    assert "unknown channel unknown_channel" in get_in(invalid.metadata, ["validation_errors"])
    assert "malformed requirement env:" in get_in(invalid.metadata, ["validation_errors"])

    refute Runtime.skill_prompt_context(agent.id, %{
             channel: "cli",
             tool_names: ["shell_command"]
           }) =~ "Invalid Skill"

    refute Runtime.skill_prompt_context(agent.id, %{
             channel: "cli",
             tool_names: ["shell_command"]
           }) =~ "Release Gated"

    System.put_env("HYDRA_X_RELEASE_WINDOW", "1")

    on_exit(fn ->
      System.delete_env("HYDRA_X_RELEASE_WINDOW")
    end)

    context =
      Runtime.skill_prompt_context(agent.id, %{
        channel: "cli",
        tool_names: ["shell_command"]
      })

    assert context =~ "Release Gated"
    refute context =~ "Invalid Skill"
  end

  test "worker can probe enabled MCP bindings" do
    agent = create_agent()

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs MCP",
        transport: "stdio",
        command: "cat",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "mcp-probe"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{id: "mcp-1", name: "mcp_probe", arguments: %{"server" => "Docs"}}
      ])

    refute result.is_error
    assert result.summary == "probed 1 MCP bindings"
    assert [%{name: "Docs MCP", status: "ok"}] = result.result.results
  end

  test "worker can invoke enabled HTTP MCP bindings" do
    agent = create_agent()
    previous = Application.get_env(:hydra_x, :mcp_http_request_fn)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      assert opts[:url] == "https://mcp.example.test/invoke"
      assert {"authorization", "Bearer mcp-secret"} in (opts[:headers] || [])
      assert opts[:json][:action] == "search_docs"
      assert opts[:json][:params] == %{"query" => "hydra"}
      {:ok, %{status: 200, body: %{"results" => [%{"title" => "Hydra docs"}]}}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs HTTP MCP",
        transport: "http",
        url: "https://mcp.example.test",
        auth_token: "mcp-secret",
        metadata: %{"slug" => "docs-http"},
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "mcp-invoke"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{
          id: "mcp-invoke-1",
          name: "mcp_invoke",
          arguments: %{
            "server" => "docs-http",
            "action" => "search_docs",
            "params" => %{"query" => "hydra"}
          }
        }
      ])

    refute result.is_error
    assert result.summary == "invoked search_docs on 1 MCP bindings"

    assert [%{name: "Docs HTTP MCP", status: "ok", result: %{status: 200}}] =
             result.result.results
  end

  test "worker can list actions on enabled HTTP MCP bindings" do
    agent = create_agent()
    previous = Application.get_env(:hydra_x, :mcp_http_request_fn)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      assert opts[:url] == "https://mcp.example.test/actions"

      {:ok,
       %{
         status: 200,
         body: %{"actions" => [%{"name" => "search_docs"}, %{"name" => "get_status"}]}
       }}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs HTTP MCP",
        transport: "http",
        url: "https://mcp.example.test",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "mcp-actions"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{id: "mcp-actions-1", name: "mcp_catalog", arguments: %{"server" => "Docs"}}
      ])

    refute result.is_error
    assert result.summary == "listed actions for 1 MCP bindings"

    assert [
             %{
               name: "Docs HTTP MCP",
               status: "ok",
               actions: ["search_docs", "get_status"],
               catalog_source: "live"
             }
           ] =
             result.result.results
  end

  test "worker can invoke enabled stdio MCP bindings" do
    agent = create_agent()
    previous = Application.get_env(:hydra_x, :mcp_stdio_runner)

    Application.put_env(:hydra_x, :mcp_stdio_runner, fn command, args, opts ->
      assert command == "fake-mcp"
      assert args == ["--mode", "json"]

      assert %{"action" => "search_docs", "op" => "invoke", "params" => %{"query" => "hydra"}} =
               Jason.decode!(opts[:input])

      {:ok,
       %{
         output: Jason.encode!(%{"text" => "Search complete", "result" => %{"hits" => 1}}),
         status: 0
       }}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_stdio_runner, previous)
      else
        Application.delete_env(:hydra_x, :mcp_stdio_runner)
      end
    end)

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs STDIO MCP",
        transport: "stdio",
        command: "fake-mcp",
        args_csv: "--mode,json",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "mcp-invoke-stdio"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{
          id: "mcp-invoke-stdio-1",
          name: "mcp_invoke",
          arguments: %{
            "server" => "Docs",
            "action" => "search_docs",
            "params" => %{"query" => "hydra"}
          }
        }
      ])

    refute result.is_error
    assert result.summary == "invoked search_docs on 1 MCP bindings"

    assert [
             %{
               name: "Docs STDIO MCP",
               status: "ok",
               result: %{status: 0, transport: "stdio_mcp_v1", data: %{"hits" => 1}}
             }
           ] = result.result.results
  end

  test "worker can list actions on enabled stdio bindings" do
    agent = create_agent()
    previous = Application.get_env(:hydra_x, :mcp_stdio_runner)

    Application.put_env(:hydra_x, :mcp_stdio_runner, fn command, _args, opts ->
      assert command == "fake-mcp"
      assert %{"op" => "actions"} = Jason.decode!(opts[:input])

      {:ok,
       %{
         output:
           Jason.encode!(%{
             "actions" => [
               %{"name" => "search_docs", "description" => "Search docs"},
               %{"name" => "get_status", "description" => "Get status"}
             ]
           }),
         status: 0
       }}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_stdio_runner, previous)
      else
        Application.delete_env(:hydra_x, :mcp_stdio_runner)
      end
    end)

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs STDIO MCP",
        transport: "stdio",
        command: "fake-mcp",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    {:ok, pid} = HydraX.Agent.ensure_started(agent)
    on_exit(fn -> if Process.alive?(pid), do: shutdown_process(pid) end)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "mcp-actions-stdio"})

    [result] =
      Worker.execute_tool_calls(agent.id, conversation, [
        %{id: "mcp-actions-stdio-1", name: "mcp_catalog", arguments: %{"server" => "Docs"}}
      ])

    refute result.is_error
    assert result.summary == "listed actions for 1 MCP bindings"

    assert [
             %{
               name: "Docs STDIO MCP",
               status: "ok",
               actions: ["search_docs", "get_status"],
               catalog_source: "live"
             }
           ] = result.result.results
  end

  test "cached MCP action catalogs can be reused without live requests" do
    agent = create_agent()
    previous = Application.get_env(:hydra_x, :mcp_http_request_fn)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn opts ->
      assert opts[:url] == "https://mcp.example.test/actions"

      {:ok,
       %{
         status: 200,
         body: %{
           "actions" => [
             %{"name" => "search_docs", "description" => "Search docs"},
             %{"name" => "get_status", "description" => "Get status"}
           ]
         }
       }}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :mcp_http_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :mcp_http_request_fn)
      end
    end)

    {:ok, _mcp} =
      Runtime.save_mcp_server(%{
        name: "Docs HTTP MCP",
        transport: "http",
        url: "https://mcp.example.test",
        enabled: true
      })

    assert {:ok, _bindings} = Runtime.refresh_agent_mcp_servers(agent.id)
    assert {:ok, %{results: [_]}} = Runtime.list_agent_mcp_actions(agent.id, refresh: true)

    Application.put_env(:hydra_x, :mcp_http_request_fn, fn _opts ->
      flunk("cached MCP action lookup should not perform a live HTTP request")
    end)

    assert {:ok, %{results: [result]}} = Runtime.list_agent_mcp_actions(agent.id)
    assert result.actions == ["search_docs", "get_status"]
    assert result.catalog_source == "live"

    assert [%{"name" => "search_docs"}, %{"name" => "get_status"}] =
             result.action_catalog["actions"]
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
    assert channel_state.recovery_lineage["recovery_count"] == 1
    assert channel_state.recovery_lineage["turn_scope_id"] == user_turn.id

    assert Enum.any?(channel_state.steps, fn step ->
             step["kind"] == "provider" and step["retry_state"]["attempt_count"] == 1 and
               step["retry_state"]["last_status"] == "completed"
           end)
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
    Process.sleep(300)

    memories =
      Memory.list_memories(agent_id: agent.id)
      |> Enum.filter(&(&1.content == "Remember cached tool result."))

    assert length(memories) == 1

    refreshed = Runtime.get_conversation!(conversation.id)
    assert List.last(refreshed.turns).content =~ "Recovered without re-running the tool."

    channel_state = Runtime.conversation_channel_state(conversation.id)

    assert Enum.any?(channel_state.execution_events, fn event ->
             event["phase"] == "tool_cache_hit" and event["details"]["cache_hits"] == 1
           end)

    assert channel_state.tool_cache_scope_turn_id == user_turn.id

    assert Enum.any?(
             channel_state.tool_results,
             &(&1["tool_name"] == "memory_save" and &1["cached"] and
                 &1["result_source"] == "cache")
           )

    assert Enum.any?(channel_state.steps, fn step ->
             step["name"] == "memory_save" and step["cached"] and step["result_source"] == "cache" and
               step["replay_count"] == 1 and step["lifecycle"] == "cached"
           end)
  end

  test "tool steps remain distinct when the provider requests the same tool twice" do
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
                        "id" => "call-recall-1",
                        "function" => %{
                          "name" => "memory_recall",
                          "arguments" => Jason.encode!(%{"query" => "release plan"})
                        }
                      },
                      %{
                        "id" => "call-recall-2",
                        "function" => %{
                          "name" => "memory_recall",
                          "arguments" => Jason.encode!(%{"query" => "release plan"})
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
                    "content" => "Captured both recall calls independently.",
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
        name: "Duplicate Tool Provider",
        kind: "openai_compatible",
        base_url: "https://duplicate-tool.test",
        api_key: "secret",
        model: "gpt-duplicate-tool",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id
      })

    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "duplicate-tool-steps"})

    response =
      HydraX.Agent.Channel.submit(
        agent,
        conversation,
        "Recall the release plan twice so I can compare it.",
        %{"source" => "test"}
      )

    assert response == "Captured both recall calls independently."

    channel_state = Runtime.conversation_channel_state(conversation.id)

    recall_steps =
      Enum.filter(channel_state.steps, fn step ->
        step["name"] == "memory_recall"
      end)

    assert length(recall_steps) == 2

    assert Enum.sort(Enum.map(recall_steps, & &1["tool_use_id"])) == [
             "call-recall-1",
             "call-recall-2"
           ]

    assert Enum.any?(recall_steps, &(&1["id"] == "tool-1-memory_recall"))
    assert Enum.any?(recall_steps, &(&1["id"] == "tool-use-call-recall-2"))

    assert Enum.all?(recall_steps, fn step ->
             step["status"] == "completed" and step["lifecycle"] == "completed" and
               step["retry_state"]["attempt_count"] == 1 and
               step["retry_state"]["last_status"] == "completed" and
               length(step["attempt_history"] || []) == 2
           end)
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
    assert is_map(hd(recall.results).score_breakdown)
  end

  test "provider and channel secrets are encrypted at rest but decrypted through runtime" do
    agent = create_agent()
    previous_provider_env = System.get_env("HYDRA_X_TEST_PROVIDER_API_KEY")

    System.put_env("HYDRA_X_TEST_PROVIDER_API_KEY", "provider-secret")

    on_exit(fn ->
      restore_env("HYDRA_X_TEST_PROVIDER_API_KEY", previous_provider_env)
    end)

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Encrypted Provider",
        kind: "openai_compatible",
        base_url: "https://encrypted-provider.test",
        api_key: "env:HYDRA_X_TEST_PROVIDER_API_KEY",
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

    assert Secrets.env_reference?(raw_provider.api_key)
    assert Secrets.env_reference_var(raw_provider.api_key) == "HYDRA_X_TEST_PROVIDER_API_KEY"
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
    assert secrets.encrypted_records >= 6
    assert secrets.env_backed_records >= 1
    assert secrets.unresolved_env_records == 0
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
      "---\nname: Deploy Checks\nsummary: Run deployment verification steps for staged rollouts.\nversion: 1.2.0\ntools: shell_command\nchannels: cli\n---\n# Deploy Checks\n\nRun deployment verification steps for staged rollouts."
    )

    assert {:ok, skills} = Runtime.refresh_agent_skills(agent.id)
    skill = Enum.find(skills, &(&1.slug == "deploy-checks"))

    refute is_nil(skill)
    assert skill.slug == "deploy-checks"
    assert skill.enabled
    assert get_in(skill.metadata, ["version"]) == "1.2.0"
    assert get_in(skill.metadata, ["tools"]) == ["shell_command"]
    assert get_in(skill.metadata, ["channels"]) == ["cli"]

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
    assert system.content =~ "version 1.2.0"
    assert system.content =~ "tools shell_command"
    assert system.content =~ "channels cli"
    assert system.content =~ "## MCP Integrations"
    assert system.content =~ "Docs MCP"

    assert Runtime.mcp_prompt_context(other_agent.id) == ""
    Runtime.disable_agent_mcp_server!(binding.id)
    assert Runtime.mcp_prompt_context(agent.id) == ""
  end

  test "skill prompt context filters by channel and available tools" do
    agent = create_agent()
    deploy_dir = Path.join([agent.workspace_root, "skills", "deploy-checks"])
    File.mkdir_p!(deploy_dir)

    File.write!(
      Path.join(deploy_dir, "SKILL.md"),
      "---\nname: Deploy Checks\nsummary: Run deployment verification steps.\ntools: shell_command,web_search\nchannels: cli,slack\n---\n# Deploy Checks"
    )

    browser_dir = Path.join([agent.workspace_root, "skills", "browser-guide"])
    File.mkdir_p!(browser_dir)

    File.write!(
      Path.join(browser_dir, "SKILL.md"),
      "---\nname: Browser Guide\nsummary: Inspect web pages.\ntools: browser_automation\nchannels: webchat\n---\n# Browser Guide"
    )

    assert {:ok, _skills} = Runtime.refresh_agent_skills(agent.id)

    cli_context =
      Runtime.skill_prompt_context(agent.id, %{
        channel: "cli",
        tool_names: ["shell_command", "web_search"]
      })

    assert cli_context =~ "Deploy Checks"
    refute cli_context =~ "Browser Guide"

    webchat_context =
      Runtime.skill_prompt_context(agent.id, %{
        channel: "webchat",
        tool_names: ["browser_automation"]
      })

    assert webchat_context =~ "Browser Guide"
    refute webchat_context =~ "Deploy Checks"
  end

  test "skill catalog can be exported for an agent" do
    agent = create_agent()
    skill_dir = Path.join([agent.workspace_root, "skills", "deploy-checks"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: Deploy Checks\nsummary: Run deployment verification steps for staged rollouts.\nversion: 1.2.0\ntags: deploy,release\ntools: shell_command\nchannels: cli\nrequires: release-window\n---\n# Deploy Checks\n\nRun deployment verification steps for staged rollouts."
    )

    assert {:ok, skills} = Runtime.refresh_agent_skills(agent.id)
    assert Enum.any?(skills, &(&1.slug == "deploy-checks"))

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-skill-catalog-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(output_root) end)

    assert {:ok, path} = Runtime.export_skill_catalog(agent.id, output_root)
    assert File.exists?(path)

    assert File.read!(path) =~ "\"slug\": \"deploy-checks\""
    assert File.read!(path) =~ "\"version\": \"1.2.0\""
    assert File.read!(path) =~ "\"tools\": ["
  end

  test "hybrid recall persists explicit embeddings and exposes vector scores" do
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
    assert is_list(get_in(top.entry.metadata || %{}, ["embedding_vector"]))
    assert get_in(top.entry.metadata || %{}, ["embedding_backend"]) == "local_hash_v1"
    assert get_in(top.entry.metadata || %{}, ["embedding_dimensions"]) == 64
    assert is_map(get_in(top.entry.metadata || %{}, ["semantic_vector"]))
    assert top.vector_score > 0.0
    assert "embedding similarity" in top.reasons

    assert {:ok, %{results: [result | _]}} =
             HydraX.Tools.MemoryRecall.execute(
               %{"agent_id" => agent.id, "query" => "cluster worker placement failover"},
               %{}
             )

    assert result["vector_score"] || result[:vector_score]
    assert (result["embedding_backend"] || result[:embedding_backend]) == "local_hash_v1"
    assert is_map(result["score_breakdown"] || result[:score_breakdown])
  end

  test "memory embeddings can use an OpenAI-compatible backend when configured" do
    agent = create_agent()
    previous_backend = System.get_env("HYDRA_X_EMBEDDING_BACKEND")
    previous_url = System.get_env("HYDRA_X_EMBEDDING_URL")
    previous_key = System.get_env("HYDRA_X_EMBEDDING_API_KEY")
    previous_model = System.get_env("HYDRA_X_EMBEDDING_MODEL")
    previous_request_fn = Application.get_env(:hydra_x, :embedding_request_fn)

    System.put_env("HYDRA_X_EMBEDDING_BACKEND", "openai_compatible")
    System.put_env("HYDRA_X_EMBEDDING_URL", "https://embeddings.example.test/v1/embeddings")
    System.put_env("HYDRA_X_EMBEDDING_API_KEY", "embed-secret")
    System.put_env("HYDRA_X_EMBEDDING_MODEL", "text-embedding-3-small")

    Application.put_env(:hydra_x, :embedding_request_fn, fn opts ->
      assert opts[:url] == "https://embeddings.example.test/v1/embeddings"
      assert {"authorization", "Bearer embed-secret"} in (opts[:headers] || [])
      assert opts[:json][:model] == "text-embedding-3-small"

      {:ok,
       %{
         status: 200,
         body: %{"data" => [%{"embedding" => [0.11, 0.22, 0.33, 0.44]}]}
       }}
    end)

    on_exit(fn ->
      restore_env("HYDRA_X_EMBEDDING_BACKEND", previous_backend)
      restore_env("HYDRA_X_EMBEDDING_URL", previous_url)
      restore_env("HYDRA_X_EMBEDDING_API_KEY", previous_key)
      restore_env("HYDRA_X_EMBEDDING_MODEL", previous_model)

      if previous_request_fn do
        Application.put_env(:hydra_x, :embedding_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :embedding_request_fn)
      end
    end)

    {:ok, memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Remote embedding support should route through an OpenAI-compatible endpoint.",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    assert get_in(memory.metadata || %{}, ["embedding_backend"]) == "openai_compatible"
    assert get_in(memory.metadata || %{}, ["embedding_model"]) == "text-embedding-3-small"
    assert get_in(memory.metadata || %{}, ["embedding_dimensions"]) == 4
    assert get_in(memory.metadata || %{}, ["embedding_vector"]) == [0.11, 0.22, 0.33, 0.44]
  end

  test "memory embedding status tracks fallback and stale records" do
    agent = create_agent()
    previous_backend = System.get_env("HYDRA_X_EMBEDDING_BACKEND")
    previous_url = System.get_env("HYDRA_X_EMBEDDING_URL")
    previous_key = System.get_env("HYDRA_X_EMBEDDING_API_KEY")
    previous_model = System.get_env("HYDRA_X_EMBEDDING_MODEL")
    previous_request_fn = Application.get_env(:hydra_x, :embedding_request_fn)

    System.put_env("HYDRA_X_EMBEDDING_BACKEND", "openai_compatible")
    System.put_env("HYDRA_X_EMBEDDING_URL", "https://embeddings.example.test/v1/embeddings")
    System.put_env("HYDRA_X_EMBEDDING_API_KEY", "embed-secret")
    System.put_env("HYDRA_X_EMBEDDING_MODEL", "text-embedding-3-small")

    on_exit(fn ->
      restore_env("HYDRA_X_EMBEDDING_BACKEND", previous_backend)
      restore_env("HYDRA_X_EMBEDDING_URL", previous_url)
      restore_env("HYDRA_X_EMBEDDING_API_KEY", previous_key)
      restore_env("HYDRA_X_EMBEDDING_MODEL", previous_model)

      if previous_request_fn do
        Application.put_env(:hydra_x, :embedding_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :embedding_request_fn)
      end
    end)

    Application.put_env(:hydra_x, :embedding_request_fn, fn _opts ->
      {:ok, %{status: 200, body: %{"data" => [%{"embedding" => [0.21, 0.31, 0.41, 0.51]}]}}}
    end)

    {:ok, remote_memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "OpenAI-compatible embeddings should stay primary when healthy.",
        importance: 0.7,
        last_seen_at: DateTime.utc_now()
      })

    assert get_in(remote_memory.metadata || %{}, ["embedding_backend"]) == "openai_compatible"
    refute get_in(remote_memory.metadata || %{}, ["embedding_fallback_from"])

    Application.put_env(:hydra_x, :embedding_request_fn, fn _opts ->
      {:error, :timeout}
    end)

    {:ok, fallback_memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Fact",
        content: "Fallback embeddings should remain queryable when the remote backend is down.",
        importance: 0.6,
        last_seen_at: DateTime.utc_now()
      })

    assert get_in(fallback_memory.metadata || %{}, ["embedding_backend"]) == "local_hash_v1"

    assert get_in(fallback_memory.metadata || %{}, ["embedding_fallback_from"]) ==
             "openai_compatible"

    status = Runtime.memory_triage_status(agent.id)

    assert status.embedding.total_count == 2
    assert status.embedding.embedded_count == 2
    assert status.embedding.unembedded_count == 0
    assert status.embedding.fallback_count == 1
    assert status.embedding.stale_count == 1
    assert status.embedding.active_backend == "openai_compatible"
    assert status.embedding.active_model == "text-embedding-3-small"
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

  test "provider capability resolution includes mock fallback" do
    mock_caps = Runtime.provider_capabilities(nil)

    assert mock_caps.mock
    refute mock_caps.streaming
  end

  test "system status exposes the repo database path" do
    system = Runtime.system_status()

    assert is_binary(system.database_path)
    assert String.ends_with?(system.database_path, ".db")
    assert system.database_url == nil
    assert system.persistence.backend == "sqlite"
    assert system.persistence.target == system.database_path
    assert system.persistence.backup_mode == "bundled_database"
    assert system.coordination.mode == "local_single_node"
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
    assert snapshot.database_url == nil
    assert snapshot.persistence.backend == "sqlite"
    assert snapshot.persistence.target == snapshot.database_path
    assert snapshot.coordination.mode == "local_single_node"
    assert is_binary(snapshot.workspace_root)
    assert is_binary(snapshot.backup_root)
    assert snapshot.cluster.mode == "single_node"
    assert is_map(snapshot.readiness)
  end

  test "cluster status reports single-node sqlite posture by default" do
    status = Runtime.cluster_status()

    refute status.enabled
    assert status.mode == "single_node"
    assert status.persistence == "sqlite_single_writer"
    refute status.multi_node_ready
    assert status.node_count >= 1
  end

  test "readiness warns when cluster awareness is enabled on sqlite" do
    previous = Application.get_env(:hydra_x, :cluster_enabled)
    Application.put_env(:hydra_x, :cluster_enabled, true)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:hydra_x, :cluster_enabled)
      else
        Application.put_env(:hydra_x, :cluster_enabled, previous)
      end
    end)

    item =
      Runtime.readiness_report().items
      |> Enum.find(&(&1.id == "cluster"))

    assert item.status == :warn
    assert item.detail =~ "SQLite"
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
    assert_receive {:job_delivery, %{chat_id: "9001", text: content}}
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
    assert_receive {:discord_job_delivery, %{channel_id: "discord-channel", content: content}}
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

  test "scheduled jobs skip duplicate execution when another node owns the job lease" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)
    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    agent = create_agent()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Remote-owned backup",
        kind: "backup",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, _lease} =
             Runtime.claim_lease("scheduled_job:#{job.id}",
               owner: "node:remote",
               ttl_seconds: 120
             )

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "skipped"
    assert run.metadata["status_reason"] == "lease_owned_elsewhere"
    assert run.metadata["lease_owner"] == "node:remote"
    assert run.output =~ "execution already owned by node:remote"
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
    assert_receive {:slack_job_delivery, %{channel: "slack-channel", text: content}}
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

  test "autonomy cycle delegates research from a planner and finalizes after worker completion" do
    planner =
      create_agent()
      |> then(fn agent -> Runtime.get_agent!(agent.id) end)

    {:ok, planner} = Runtime.save_agent(planner, %{"role" => "planner"})

    researcher =
      create_agent()
      |> then(fn agent -> Runtime.get_agent!(agent.id) end)

    {:ok, researcher} = Runtime.save_agent(researcher, %{"role" => "researcher"})

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: researcher.id,
        type: "Fact",
        content: "Hydra-X should capture provenance and confidence in research reports.",
        importance: 0.8,
        metadata: %{
          "source_file" => "ops/research.md",
          "source_section" => "autonomy",
          "source_channel" => "cli"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Assess how Hydra should deliver autonomous research summaries.",
        "assigned_agent_id" => planner.id,
        "assigned_role" => "planner",
        "execution_mode" => "delegate",
        "priority" => 7
      })

    assert {:ok, planner_summary} = Runtime.run_autonomy_cycle(planner.id)
    assert planner_summary.action == "delegated"

    parent = Runtime.get_work_item!(parent.id)
    assert parent.status == "blocked"
    [child_id] = parent.result_refs["child_work_item_ids"]

    child = Runtime.get_work_item!(child_id)
    assert child.assigned_role == "researcher"
    assert child.parent_work_item_id == parent.id

    assert {:ok, researcher_summary} = Runtime.run_autonomy_cycle(researcher.id)
    assert researcher_summary.action == "researched"

    child = Runtime.get_work_item!(child.id)
    assert child.status == "completed"
    assert length(child.result_refs["artifact_ids"]) == 3

    artifacts = Runtime.work_item_artifacts(child.id)
    report = Enum.find(artifacts, &(&1.type == "research_report"))
    decision_ledger = Enum.find(artifacts, &(&1.type == "decision_ledger"))

    assert report
    assert decision_ledger
    assert report.payload["question"] =~ "Assess how Hydra"
    assert length(report.payload["evidence"]) >= 1
    assert is_float(report.confidence)

    assert {:ok, finalize_summary} = Runtime.run_autonomy_cycle(planner.id)
    assert finalize_summary.action == "finalized_blocked_parent"

    parent = Runtime.get_work_item!(parent.id)
    assert parent.status == "completed"
    assert length(parent.result_refs["artifact_ids"]) >= 1
  end

  test "planner delegation carries artifact-derived context into child research work" do
    planner =
      create_agent()
      |> then(&Runtime.get_agent!(&1.id))

    {:ok, planner} = Runtime.save_agent(planner, %{"role" => "planner"})

    researcher =
      create_agent()
      |> then(&Runtime.get_agent!(&1.id))

    {:ok, researcher} = Runtime.save_agent(researcher, %{"role" => "researcher"})

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: planner.id,
        type: "Decision",
        content: "Use approved report exports as the primary operator-facing research surface.",
        importance: 0.87,
        metadata: %{
          "memory_scope" => "artifact_derived",
          "source_work_item_id" => 101,
          "source_artifact_type" => "decision_ledger"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, parent} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Assess the best operator-facing surface for approved research findings.",
        "assigned_agent_id" => planner.id,
        "assigned_role" => "planner",
        "execution_mode" => "delegate",
        "priority" => 7,
        "metadata" => %{"delegate_role" => "researcher"}
      })

    assert {:ok, planner_summary} = Runtime.run_autonomy_cycle(planner.id)
    assert planner_summary.action == "delegated"

    parent = Runtime.get_work_item!(parent.id)
    [child_id] = parent.result_refs["child_work_item_ids"]
    child = Runtime.get_work_item!(child_id)

    delegated_context = get_in(child.metadata || %{}, ["delegation_context", "promoted_memories"])
    assert is_list(delegated_context)

    assert Enum.any?(delegated_context, fn memory ->
             memory["content"] =~ "primary operator-facing research surface"
           end)

    assert {:ok, researcher_summary} = Runtime.run_autonomy_cycle(researcher.id)
    assert researcher_summary.action == "researched"

    report =
      Runtime.work_item_artifacts(child.id)
      |> Enum.find(&(&1.type == "research_report"))

    assert report

    assert Enum.any?(report.payload["planning_context"] || [], fn memory ->
             memory["content"] =~ "primary operator-facing research surface"
           end)

    assert Enum.any?(report.payload["claims"] || [], fn claim ->
             claim =~ "primary operator-facing research surface"
           end)

    assert Enum.any?(report.payload["recommended_actions"] || [], fn action ->
             action =~ "Validate the delegated research findings"
           end)
  end

  test "research work items create a decision ledger and promote approved memories" do
    researcher =
      create_agent()
      |> then(fn agent -> Runtime.get_agent!(agent.id) end)

    {:ok, researcher} = Runtime.save_agent(researcher, %{"role" => "researcher"})

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: researcher.id,
        type: "Fact",
        content: "Approved research should become durable memory with provenance.",
        importance: 0.9,
        metadata: %{
          "source_file" => "ops/research.md",
          "source_section" => "promotion",
          "source_channel" => "cli"
        },
        last_seen_at: DateTime.utc_now()
      })

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Explain how approved research should promote durable memory.",
        "assigned_agent_id" => researcher.id,
        "assigned_role" => "researcher",
        "execution_mode" => "execute",
        "review_required" => false
      })

    assert {:ok, summary} = Runtime.run_autonomy_cycle(researcher.id)
    assert summary.action == "researched"

    work_item = Runtime.get_work_item!(work_item.id)
    assert work_item.approval_stage == "operator_approved"
    assert length(work_item.result_refs["promoted_memory_ids"]) >= 1

    artifacts = Runtime.work_item_artifacts(work_item.id)
    assert Enum.any?(artifacts, &(&1.type == "research_report"))
    assert Enum.any?(artifacts, &(&1.type == "decision_ledger"))

    promoted_memories =
      Memory.list_memories(agent_id: researcher.id, status: "active", limit: 50)
      |> Enum.filter(fn entry ->
        metadata = entry.metadata || %{}
        metadata["source_work_item_id"] == work_item.id
      end)

    assert Enum.any?(promoted_memories, &(&1.type == "Fact"))
    assert Enum.any?(promoted_memories, &(&1.type == "Decision"))

    assert Enum.all?(promoted_memories, fn memory ->
             metadata = memory.metadata || %{}
             metadata["memory_scope"] == "artifact_derived"
           end)

    assert Enum.all?(promoted_memories, &is_integer((&1.metadata || %{})["source_artifact_id"]))

    bulletin = Runtime.agent_bulletin(researcher.id)
    assert bulletin.content =~ "Current Decisions And Preferences"

    assert bulletin.content =~
             "Review the report and promote any durable findings into long-term memory."
  end

  test "approving a research work item promotes memories from report artifacts" do
    researcher =
      create_agent()
      |> then(fn agent -> Runtime.get_agent!(agent.id) end)

    {:ok, researcher} = Runtime.save_agent(researcher, %{"role" => "researcher"})

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Promote research findings after operator approval.",
        "assigned_agent_id" => researcher.id,
        "assigned_role" => "researcher",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {:ok, report_artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "research_report",
        "title" => "Research report",
        "summary" => "Promoted research report",
        "review_status" => "validated",
        "payload" => %{
          "question" => work_item.goal,
          "scope" => "autonomous research",
          "claims" => ["Approved findings should produce durable facts."],
          "recommended_actions" => ["Promote the research outcome into memory."],
          "open_questions" => ["What evidence should expire?"],
          "confidence" => 0.81
        }
      })

    {:ok, _ledger_artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "decision_ledger",
        "title" => "Research decision ledger",
        "summary" => "Decision ledger",
        "review_status" => "validated",
        "payload" => %{
          "summary" => "Explain the approval path and promote the durable research decision.",
          "question" => work_item.goal,
          "scope" => "autonomous research",
          "claims" => ["Approved findings should produce durable facts."],
          "recommended_actions" => ["Promote the research outcome into memory."],
          "open_questions" => ["What evidence should expire?"],
          "confidence" => 0.81
        }
      })

    {updated, _record} =
      Runtime.approve_work_item!(work_item.id, %{
        "requested_action" => "promote_work_item",
        "rationale" => "Operator approved the research findings."
      })

    assert updated.result_refs["promoted_memory_ids"] != nil
    assert length(updated.result_refs["promoted_memory_ids"]) >= 1

    promoted_memories =
      Memory.list_memories(agent_id: researcher.id, status: "active", limit: 50)
      |> Enum.filter(fn entry ->
        metadata = entry.metadata || %{}
        metadata["source_work_item_id"] == work_item.id
      end)

    assert Enum.any?(promoted_memories, &(&1.type == "Decision"))

    assert Enum.any?(promoted_memories, fn memory ->
             metadata = memory.metadata || %{}
             metadata["memory_scope"] == "artifact_derived"
           end)

    artifact_approvals = Runtime.artifact_approval_records(report_artifact.id)
    assert Enum.any?(artifact_approvals, &(&1.requested_action == "promote_work_item"))

    bulletin = Runtime.agent_bulletin(researcher.id)

    assert bulletin.content =~
             "Explain the approval path and promote the durable research decision."
  end

  test "autonomy scheduled jobs run the autonomy cycle for assigned work" do
    agent =
      create_agent()
      |> then(fn current -> Runtime.get_agent!(current.id) end)

    {:ok, agent} = Runtime.save_agent(agent, %{"role" => "researcher"})

    {:ok, _work_item} =
      Runtime.save_work_item(%{
        "kind" => "research",
        "goal" => "Summarize the current autonomous work posture.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "researcher",
        "execution_mode" => "execute"
      })

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Autonomy sweep",
        kind: "autonomy",
        schedule_mode: "interval",
        interval_minutes: 60,
        enabled: true
      })

    assert {:ok, run} = Runtime.run_scheduled_job(job)
    assert run.status == "success"
    assert run.output =~ "Autonomy cycle processed"
    assert run.metadata["artifact_count"] >= 1

    [work_item] = Runtime.list_work_items(agent_id: agent.id, limit: 10)
    assert work_item.status == "completed"
  end

  test "autonomy status reports configured roles and recent work items" do
    agent =
      create_agent()
      |> then(fn current -> Runtime.get_agent!(current.id) end)

    {:ok, agent} = Runtime.save_agent(agent, %{"role" => "planner"})

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Prepare the next autonomy rollout.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "planner",
        "status" => "planned"
      })

    status = Runtime.autonomy_status()

    assert status.autonomy_agent_count >= 1
    assert Map.get(status.active_roles, "planner", 0) >= 1
    assert Map.get(status.counts, "planned", 0) >= 1
    assert Enum.any?(status.recent_work_items, &(&1.id == work_item.id))
  end

  test "engineering work items create proposal, change set, review, and approval records" do
    builder =
      create_agent()
      |> then(&Runtime.get_agent!(&1.id))

    {:ok, builder} = Runtime.save_agent(builder, %{"role" => "builder"})

    reviewer =
      create_agent()
      |> then(&Runtime.get_agent!(&1.id))

    {:ok, reviewer} = Runtime.save_agent(reviewer, %{"role" => "reviewer"})

    {:ok, delegated_memory} =
      Memory.create_memory(%{
        agent_id: builder.id,
        type: "Decision",
        content: "Keep validated runtime approval guidance visible during engineering review.",
        importance: 0.86,
        metadata: %{
          "memory_scope" => "artifact_derived",
          "source_work_item_id" => 202,
          "source_artifact_type" => "decision_ledger"
        },
        last_seen_at: DateTime.utc_now()
      })

    File.write!(Path.join(builder.workspace_root, "README.md"), "# Hydra-X\n")
    File.mkdir_p!(Path.join(builder.workspace_root, "lib"))

    File.write!(
      Path.join(builder.workspace_root, "lib/runtime_notes.ex"),
      "defmodule RuntimeNotes do\nend\n"
    )

    {:ok, parent} =
      Runtime.save_work_item(%{
        "kind" => "engineering",
        "goal" => "Improve the runtime approval pipeline for autonomous work.",
        "assigned_agent_id" => builder.id,
        "assigned_role" => "builder",
        "execution_mode" => "execute",
        "priority" => 9,
        "review_required" => true,
        "metadata" => %{
          "delegation_context" => %{
            "source_agent_id" => builder.id,
            "query" => "runtime approval pipeline",
            "captured_at" => DateTime.utc_now(),
            "promoted_memories" => [
              %{
                "memory_id" => delegated_memory.id,
                "type" => "Decision",
                "content" => delegated_memory.content,
                "score" => 1.2,
                "reasons" => ["artifact-derived memory"],
                "score_breakdown" => %{"artifact" => 1.2},
                "source_work_item_id" => 202,
                "source_artifact_type" => "decision_ledger"
              }
            ]
          }
        }
      })

    assert {:ok, builder_summary} = Runtime.run_autonomy_cycle(builder.id)
    assert builder_summary.action == "engineering_review_requested"

    parent = Runtime.get_work_item!(parent.id)
    assert parent.status == "blocked"
    assert parent.approval_stage == "patch_ready"

    parent_artifacts = Runtime.work_item_artifacts(parent.id)
    assert Enum.any?(parent_artifacts, &(&1.type == "proposal"))
    assert Enum.any?(parent_artifacts, &(&1.type == "code_change_set"))

    [review_item_id] = parent.result_refs["child_work_item_ids"]
    review_item = Runtime.get_work_item!(review_item_id)
    assert review_item.kind == "review"
    assert review_item.assigned_role == "reviewer"

    delegated_context =
      get_in(review_item.metadata || %{}, ["delegation_context", "promoted_memories"]) || []

    assert delegated_context != []

    assert Enum.any?(
             delegated_context,
             &String.contains?(&1["content"], "validated runtime approval guidance")
           )

    assert {:ok, reviewer_summary} = Runtime.run_autonomy_cycle(reviewer.id)
    assert reviewer_summary.action == "review_completed"

    review_item = Runtime.get_work_item!(review_item.id)
    review_artifacts = Runtime.work_item_artifacts(review_item.id)
    assert Enum.any?(review_artifacts, &(&1.type == "review_report"))
    assert Enum.any?(review_artifacts, &(&1.type == "decision_ledger"))
    assert length(review_item.result_refs["promoted_memory_ids"] || []) >= 1

    review_report = Enum.find(review_artifacts, &(&1.type == "review_report"))

    assert Enum.any?(review_report.payload["delegated_context"] || [], fn memory ->
             memory["content"] =~ "validated runtime approval guidance"
           end)

    approvals = Runtime.approval_records_for_subject("work_item", parent.id)
    assert Enum.any?(approvals, &(&1.decision == "approved"))

    reviewer_memories =
      Memory.list_memories(agent_id: reviewer.id, status: "active", limit: 50)
      |> Enum.filter(fn entry ->
        metadata = entry.metadata || %{}
        metadata["source_work_item_id"] == review_item.id
      end)

    assert Enum.any?(reviewer_memories, &(&1.type == "Decision"))

    assert Enum.all?(reviewer_memories, fn memory ->
             metadata = memory.metadata || %{}
             metadata["memory_origin_role"] == "reviewer"
           end)

    assert {:ok, finalize_summary} = Runtime.run_autonomy_cycle(builder.id)
    assert finalize_summary.action == "finalized_blocked_parent"

    parent = Runtime.get_work_item!(parent.id)
    assert parent.status == "completed"
    assert parent.approval_stage == "validated"
    assert length(parent.result_refs["approval_record_ids"]) >= 1
  end

  test "operator approval records can promote a work item" do
    agent = create_agent()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "task",
        "goal" => "Promote the reviewed work item.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "operator",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {updated, record} =
      Runtime.approve_work_item!(work_item.id, %{
        "requested_action" => "merge_ready",
        "rationale" => "Operator approved promotion to merge-ready state."
      })

    assert updated.approval_stage == "merge_ready"
    assert record.decision == "approved"
    assert record.requested_action == "merge_ready"

    approvals = Runtime.approval_records_for_subject("work_item", work_item.id)
    assert Enum.any?(approvals, &(&1.id == record.id))
  end

  test "artifact approvals are recorded for parent promotion and direct artifact decisions" do
    agent = create_agent()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "engineering",
        "goal" => "Track artifact approval history.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {:ok, artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "code_change_set",
        "title" => "Tracked patch",
        "summary" => "Track patch promotion history",
        "review_status" => "validated"
      })

    {_updated, _record} =
      Runtime.approve_work_item!(work_item.id, %{
        "requested_action" => "merge_ready",
        "rationale" => "Promoted through the parent work item."
      })

    artifact_approvals = Runtime.artifact_approval_records(artifact.id)
    assert Enum.any?(artifact_approvals, &(&1.requested_action == "merge_ready"))

    {rejected_artifact, rejection_record} =
      Runtime.reject_artifact!(artifact.id, %{
        "requested_action" => "publish_review_report",
        "rationale" => "Artifact-specific rejection."
      })

    assert rejected_artifact.review_status == "rejected"
    assert rejection_record.subject_type == "artifact"

    artifact_approvals = Runtime.artifact_approval_records(artifact.id)
    assert Enum.any?(artifact_approvals, &(&1.decision == "approved"))
    assert Enum.any?(artifact_approvals, &(&1.decision == "rejected"))
  end

  test "extension work items produce approval-gated package metadata" do
    builder =
      create_agent()
      |> then(&Runtime.get_agent!(&1.id))

    {:ok, builder} = Runtime.save_agent(builder, %{"role" => "builder"})

    File.mkdir_p!(Path.join(builder.workspace_root, "priv/extensions"))
    File.write!(Path.join(builder.workspace_root, "README.md"), "# Hydra-X extensions\n")

    {:ok, extension_item} =
      Runtime.save_work_item(%{
        "kind" => "extension",
        "goal" => "Create a plugin package for design review automation.",
        "assigned_agent_id" => builder.id,
        "assigned_role" => "builder",
        "execution_mode" => "execute",
        "review_required" => false
      })

    assert {:ok, summary} = Runtime.run_autonomy_cycle(builder.id)
    assert summary.action == "engineering_completed"

    extension_item = Runtime.get_work_item!(extension_item.id)
    assert extension_item.approval_stage == "validated"

    patch_bundle =
      Runtime.work_item_artifacts(extension_item.id)
      |> Enum.find(&(&1.type == "patch_bundle"))

    assert patch_bundle
    assert patch_bundle.payload["extension_package"]["package_type"] == "hydra_extension"
    assert patch_bundle.payload["registration"]["enablement_status"] == "approval_required"
    assert patch_bundle.payload["registration"]["install_mode"] == "manual_registration"

    assert patch_bundle.payload["compatibility"]["required_roles"] == [
             "builder",
             "reviewer",
             "operator"
           ]

    {approved_item, record} =
      Runtime.approve_work_item!(extension_item.id, %{
        "requested_action" => "enable_extension",
        "rationale" => "Operator approved extension registration."
      })

    assert approved_item.approval_stage == "operator_approved"
    assert approved_item.result_refs["extension_enablement_status"] == "approved_not_enabled"
    assert record.requested_action == "enable_extension"

    artifact_approvals = Runtime.artifact_approval_records(patch_bundle.id)
    assert Enum.any?(artifact_approvals, &(&1.requested_action == "validate_artifact"))
    assert Enum.any?(artifact_approvals, &(&1.requested_action == "enable_extension"))
  end

  test "operator rejection records fail a reviewed work item" do
    agent = create_agent()

    {:ok, work_item} =
      Runtime.save_work_item(%{
        "kind" => "engineering",
        "goal" => "Reject the candidate runtime change.",
        "assigned_agent_id" => agent.id,
        "assigned_role" => "builder",
        "status" => "completed",
        "approval_stage" => "validated"
      })

    {:ok, _artifact} =
      Runtime.create_artifact(%{
        "work_item_id" => work_item.id,
        "type" => "code_change_set",
        "title" => "Candidate change set",
        "summary" => "Candidate runtime change",
        "review_status" => "validated"
      })

    {updated, record} =
      Runtime.reject_work_item!(work_item.id, %{
        "requested_action" => "merge_ready",
        "rationale" => "Operator rejected the rollout due to missing test coverage."
      })

    assert updated.status == "failed"
    assert updated.approval_stage == "validated"
    assert record.decision == "rejected"

    [artifact] = Runtime.work_item_artifacts(work_item.id)
    assert artifact.review_status == "rejected"
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

  test "provider routing can promote a fallback under budget pressure" do
    agent = create_agent()

    {:ok, primary} =
      Runtime.save_provider_config(%{
        name: "Primary Budget Route",
        kind: "openai_compatible",
        base_url: "https://primary-budget.test",
        api_key: "secret",
        model: "gpt-primary-budget",
        enabled: false
      })

    {:ok, fallback} =
      Runtime.save_provider_config(%{
        name: "Fallback Budget Route",
        kind: "openai_compatible",
        base_url: "https://fallback-budget.test",
        api_key: "secret",
        model: "gpt-fallback-budget",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => primary.id,
        "fallback_provider_ids_csv" => Integer.to_string(fallback.id)
      })

    policy = Budget.ensure_policy!(agent.id)

    {:ok, _updated} =
      Budget.save_policy(policy, %{
        agent_id: agent.id,
        daily_limit: 20,
        conversation_limit: 20,
        soft_warning_at: 0.5,
        hard_limit_action: "warn",
        enabled: true
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "cli", title: "budget-route"})

    assert {:ok, _usage} =
             Budget.record_usage(agent.id, conversation.id, %{
               scope: "llm_completion",
               tokens_in: 12,
               tokens_out: 0
             })

    route =
      Runtime.effective_provider_route(agent.id, "channel",
        conversation_id: conversation.id,
        estimated_tokens: 4
      )

    assert route.provider.id == fallback.id
    assert [remaining] = route.fallbacks
    assert remaining.id == primary.id
    assert route.source == "budget:soft_limit_reached"
    assert route.budget.warnings == [:soft_limit_reached]
  end

  test "effective policy consolidates tool, delivery, ingest, and auth rules" do
    agent = create_agent()

    {:ok, _tool_policy} =
      Runtime.save_agent_tool_policy(agent.id, %{
        browser_automation_enabled: true,
        browser_automation_channels_csv: "cli",
        shell_command_enabled: false
      })

    {:ok, _control_policy} =
      Runtime.save_agent_control_policy(agent.id, %{
        recent_auth_window_minutes: 4,
        interactive_delivery_channels_csv: "webchat",
        job_delivery_channels_csv: "discord,slack",
        ingest_roots_csv: "ingest,docs"
      })

    policy = Runtime.effective_policy(agent.id, process_type: "channel")

    assert policy.auth.recent_auth_required
    assert policy.auth.recent_auth_window_minutes == 4
    assert policy.deliveries.interactive_channels == ["webchat"]
    assert policy.deliveries.job_channels == ["discord", "slack"]
    assert policy.ingest.roots == ["ingest", "docs"]
    assert policy.routing.source in ["global", "mock"]

    assert Runtime.tool_decision(agent.id, "browser_automation", "cli").allowed?
    refute Runtime.tool_decision(agent.id, "browser_automation", "webchat").allowed?
    refute Runtime.tool_decision(agent.id, "shell_command", "cli").allowed?

    assert Runtime.authorize_delivery(agent.id, :interactive, "webchat") == :ok

    assert Runtime.authorize_delivery(agent.id, :job, "telegram") ==
             {:error, {:delivery_channel_blocked_by_policy, "telegram"}}

    assert Runtime.authorize_ingest_path(
             agent.id,
             agent.workspace_root,
             Path.join(agent.workspace_root, "docs/policy.md")
           ) == :ok

    assert Runtime.authorize_ingest_path(
             agent.id,
             agent.workspace_root,
             Path.join(System.tmp_dir!(), "outside.md")
           ) == {:error, {:ingest_path_not_allowed, ["ingest", "docs"]}}
  end

  test "effective provider route can shift background work under workload pressure" do
    agent = create_agent()

    {:ok, primary} =
      Runtime.save_provider_config(%{
        name: "Primary Scheduler Route",
        kind: "openai_compatible",
        base_url: "https://primary-scheduler.test",
        api_key: "secret",
        model: "gpt-primary-scheduler",
        enabled: false
      })

    {:ok, fallback} =
      Runtime.save_provider_config(%{
        name: "Fallback Scheduler Route",
        kind: "openai_compatible",
        base_url: "https://fallback-scheduler.test",
        api_key: "secret",
        model: "gpt-fallback-scheduler",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => primary.id,
        "fallback_provider_ids_csv" => Integer.to_string(fallback.id)
      })

    {:ok, _job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Circuit open workload",
        kind: "prompt",
        prompt: "check workload",
        schedule_mode: "interval",
        interval_minutes: 30,
        circuit_state: "open"
      })

    route = Runtime.effective_provider_route(agent.id, "scheduler")

    assert route.provider.id == fallback.id
    assert route.source == "workload:open_circuit_jobs"
    assert route.workload.applied?
    assert route.workload.pressure == "high"
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

  test "bulletin ranking reuses provenance and recency signals" do
    agent = create_agent()

    {:ok, _older_goal} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Keep the general rollout documented.",
        importance: 0.7,
        last_seen_at: DateTime.add(DateTime.utc_now(), -30, :day)
      })

    {:ok, _ranked_goal} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Goal",
        content: "Ship the Webchat bulletin refresh from ingest-backed memory.",
        importance: 0.9,
        metadata: %{
          "source" => "ingest",
          "source_file" => "ops/webchat.md",
          "source_channel" => "webchat"
        },
        last_seen_at: DateTime.utc_now()
      })

    [top | _rest] = Memory.bulletin_ranked(agent.id, 5)

    assert top.entry.content =~ "Ship the Webchat bulletin refresh"
    assert "goal memory" in top.reasons
    assert "high importance" in top.reasons
    assert "ingest provenance" in top.reasons
    assert "recently reinforced" in top.reasons
    assert "channel context" in top.reasons
    assert is_map(top.score_breakdown)
    assert top.score_breakdown["importance"] > 0
    assert top.score_breakdown["provenance"] > 0
    assert top.score_breakdown["channel"] > 0
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

    assert bulletin.content =~
             "[Observation/webchat] Webchat retries need continued operator monitoring."

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

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Prefer concise compaction summaries that preserve commitments.",
        importance: 0.95,
        metadata: %{
          "source_file" => "ops/compaction.md",
          "source_channel" => "webchat"
        }
      })

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
    assert compaction.summary_source in ["provider", "fallback"]
    assert compaction.thresholds == policy
    assert compaction.estimated_tokens > 0
    assert compaction.supporting_memories != []

    assert Enum.any?(
             compaction.supporting_memories,
             &(&1.content =~ "Prefer concise compaction summaries" and
                 is_map(&1.score_breakdown) and &1.source_file == "ops/compaction.md")
           )

    assert compaction.conversation_limit_tokens ==
             Budget.ensure_policy!(agent.id).conversation_limit

    assert compaction.token_ratio > 0.0

    reset = Runtime.reset_conversation_compaction!(conversation.id)
    assert reset.level == nil
    assert reset.summary == nil
    assert reset.supporting_memories == []
    assert reset.thresholds == policy
    assert reset.estimated_tokens > 0
    assert reset.token_ratio > 0.0
  end

  test "conversation compaction prompt includes ranked supporting memories" do
    previous_request_fn = Application.get_env(:hydra_x, :provider_request_fn)
    test_pid = self()

    Application.put_env(:hydra_x, :provider_request_fn, fn opts ->
      send(test_pid, {:compaction_prompt, opts[:json][:messages], opts[:json][:model]})

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" => "Compacted with supporting memory context.",
                 "tool_calls" => nil
               },
               "finish_reason" => "stop"
             }
           ]
         }
       }}
    end)

    on_exit(fn ->
      if previous_request_fn do
        Application.put_env(:hydra_x, :provider_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    agent = create_agent()
    Runtime.save_compaction_policy!(agent.id, %{"soft" => 4, "medium" => 8, "hard" => 12})

    {:ok, _memory} =
      Memory.create_memory(%{
        agent_id: agent.id,
        type: "Decision",
        content: "Preserve deployment commitments and keep the summary concise.",
        importance: 0.96,
        metadata: %{
          "source_file" => "ops/deploy.md",
          "source_channel" => "slack"
        }
      })

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Compaction Prompt Provider",
        kind: "openai_compatible",
        base_url: "https://compaction-prompt.test",
        api_key: "secret",
        model: "gpt-compaction-prompt",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(agent.id, %{
        "default_provider_id" => provider.id,
        "compactor_provider_id" => provider.id
      })

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{channel: "control_plane", title: "Compaction Prompt"})

    Enum.each(1..12, fn index ->
      {:ok, _turn} =
        Runtime.append_turn(conversation, %{
          role: if(rem(index, 2) == 0, do: "assistant", else: "user"),
          content: "Turn #{index} covering deployment commitments and summary constraints",
          metadata: %{}
        })
    end)

    compaction = Runtime.review_conversation_compaction!(conversation.id)

    assert_receive {:compaction_prompt, messages, "gpt-compaction-prompt"}, 1_000

    prompt = List.first(messages)[:content]

    assert prompt =~ "Supporting memories:"
    assert prompt =~ "Preserve deployment commitments and keep the summary concise."
    assert prompt =~ "breakdown="
    assert prompt =~ "Conversation transcript:"
    assert compaction.summary == "Compacted with supporting memory context."
    assert compaction.summary_source == "provider"
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

  defp wait_for(fun, attempts \\ 80)

  defp wait_for(fun, 0), do: assert(fun.())

  defp wait_for(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_for(fun, attempts - 1)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
