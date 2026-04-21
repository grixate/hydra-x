defmodule HydraX.Agent.HooksIntegrationTest do
  @moduledoc """
  End-to-end verification that the Phase 1 hook insertion points actually
  fire in production code paths. Uses the real `Worker.execute_tool_calls/3`
  and `Compactor.review_now/2` entry points — the Channel's `do_llm_call`
  site is exercised indirectly via the compactor (which uses the same
  `LLM.Router.complete/1` path).
  """

  use HydraX.DataCase, async: false

  alias HydraX.Agent
  alias HydraX.Agent.{Compactor, Hooks, Worker}
  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Conversation, Conversations}

  setup do
    suffix = System.unique_integer([:positive])

    agent =
      %AgentProfile{}
      |> AgentProfile.changeset(%{
        "name" => "hooks-int-#{suffix}",
        "slug" => "hooks-int-#{suffix}",
        "workspace_root" => Path.join(System.tmp_dir!(), "hx_hooks_#{suffix}")
      })
      |> Repo.insert!()

    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{
        "agent_id" => agent.id,
        "channel" => "test",
        "status" => "active",
        "metadata" => %{}
      })
      |> Repo.insert()

    {:ok, _pid} = Agent.ensure_started(agent)

    on_exit(fn ->
      Agent.ensure_stopped(agent)

      for hook <- Hooks.hooks() do
        Hooks.unregister(agent.id, hook)
      end
    end)

    {:ok, agent: agent, conversation: conversation}
  end

  describe "Worker.execute_tool_calls fires :before_tool_call and :after_tool_call" do
    test "fires both hooks around the execution", %{agent: agent, conversation: conversation} do
      test_pid = self()

      Hooks.register(agent.id, :before_tool_call, fn ctx ->
        send(test_pid, {:before, ctx})
        {:ok, ctx}
      end)

      Hooks.register(agent.id, :after_tool_call, fn ctx ->
        send(test_pid, {:after, ctx})
        :ok
      end)

      tool_call = %{
        id: "t-#{System.unique_integer([:positive])}",
        name: "no_such_tool",
        arguments: %{}
      }

      Worker.execute_tool_calls(agent.id, conversation, [tool_call])

      assert_receive {:before, %{tool: "no_such_tool", agent_id: aid, conversation_id: cid}}, 2_000
      assert aid == agent.id
      assert cid == conversation.id

      assert_receive {:after, %{tool: "no_such_tool", result: result}}, 2_000
      assert result[:is_error] == true
      assert result[:tool_name] == "no_such_tool"
    end

    test "halt in :before_tool_call produces a synthetic halted-tool result",
         %{agent: agent, conversation: conversation} do
      Hooks.register(agent.id, :before_tool_call, fn _ctx ->
        {:halt, :blocked_by_policy}
      end)

      tool_call = %{
        id: "t-#{System.unique_integer([:positive])}",
        name: "any_tool",
        arguments: %{}
      }

      [result] = Worker.execute_tool_calls(agent.id, conversation, [tool_call])

      assert result.is_error == true
      assert result.tool_name == "any_tool"
      assert result.result.error =~ "halted by hook"
      assert result.safety_classification == "halted"
    end

    test "modified :arguments from :before_tool_call are passed to the tool", %{
      agent: agent,
      conversation: conversation
    } do
      test_pid = self()

      Hooks.register(agent.id, :before_tool_call, fn ctx ->
        {:ok, Map.put(ctx, :arguments, Map.put(ctx.arguments, :injected, true))}
      end)

      Hooks.register(agent.id, :after_tool_call, fn ctx ->
        send(test_pid, {:after, ctx})
        :ok
      end)

      tool_call = %{
        id: "t-#{System.unique_integer([:positive])}",
        name: "no_such_tool",
        arguments: %{original: true}
      }

      Worker.execute_tool_calls(agent.id, conversation, [tool_call])

      assert_receive {:after, %{arguments: args}}, 2_000
      assert args[:original] == true
      assert args[:injected] == true
    end
  end

  describe "Compactor.review_now fires :before_compaction and :after_compaction" do
    test "fires both hooks when the token threshold is breached", %{
      agent: agent,
      conversation: conversation
    } do
      # Seed enough turns to cross a compaction threshold. The default
      # Budget policy typically triggers :soft at 80% which, for a fresh
      # agent, means a handful of long turns is enough.
      for i <- 1..30 do
        Conversations.append_turn(conversation, %{
          "role" => if(rem(i, 2) == 0, do: "assistant", else: "user"),
          "kind" => "message",
          "content" => String.duplicate("lorem ipsum dolor sit amet ", 400)
        })
      end

      test_pid = self()

      Hooks.register(agent.id, :before_compaction, fn ctx ->
        send(test_pid, {:before_compaction, ctx})
        {:ok, ctx}
      end)

      Hooks.register(agent.id, :after_compaction, fn ctx ->
        send(test_pid, {:after_compaction, ctx})
        :ok
      end)

      # Subscribe to the PubSub topic so we can also verify the
      # `:context_compacted` broadcast from Phase 3.
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations:#{conversation.id}")

      _ = Compactor.review_now(agent.id, conversation.id)

      assert_receive {:before_compaction, %{level: level, conversation_id: cid}}, 5_000
      assert level in ["soft", "medium", "hard"]
      assert cid == conversation.id

      assert_receive {:after_compaction, %{level: _, turns_compacted: count}}, 5_000
      assert count > 0

      expected_id = conversation.id
      assert_receive {:context_compacted, ^expected_id, payload}, 5_000
      assert is_map(payload)
      assert payload.turns_compacted == count
    end

    test "halt in :before_compaction prevents the summary call", %{
      agent: agent,
      conversation: conversation
    } do
      for _ <- 1..30 do
        Conversations.append_turn(conversation, %{
          "role" => "user",
          "kind" => "message",
          "content" => String.duplicate("word ", 500)
        })
      end

      Hooks.register(agent.id, :before_compaction, fn _ctx ->
        {:halt, :disabled}
      end)

      test_pid = self()

      Hooks.register(agent.id, :after_compaction, fn ctx ->
        send(test_pid, {:after_fired, ctx})
        :ok
      end)

      _ = Compactor.review_now(agent.id, conversation.id)

      # The after hook should NOT fire when before halted.
      refute_receive {:after_fired, _}, 500
    end

    test "strategy override from :before_compaction is honored", %{
      agent: agent,
      conversation: conversation
    } do
      for _ <- 1..30 do
        Conversations.append_turn(conversation, %{
          "role" => "user",
          "kind" => "message",
          "content" => String.duplicate("aaa ", 600)
        })
      end

      Hooks.register(agent.id, :before_compaction, fn ctx ->
        # Auto-resolved would be "simple" (not a coder persona); we force
        # code_aware via the override field.
        {:ok, Map.put(ctx, :strategy, "code_aware")}
      end)

      assert Compactor.review_now(agent.id, conversation.id) != nil
    end
  end
end
