defmodule HydraX.Agent.HooksTest do
  use ExUnit.Case, async: false

  alias HydraX.Agent.Hooks

  setup do
    # Each test runs in its own process, so registrations are scoped via
    # Registry's process-link behaviour. We still defensively unregister
    # known keys from previous tests via on_exit.
    on_exit(fn ->
      for hook <- Hooks.hooks() do
        Hooks.unregister(:test_agent, hook)
        Hooks.unregister_global(hook)
      end
    end)

    :ok
  end

  describe "fire/3 with no registrations" do
    test "returns the unchanged context" do
      assert {:ok, %{a: 1}} = Hooks.fire(:test_agent, :before_llm_call, %{a: 1})
    end
  end

  describe "fire/3 with a single hook" do
    test ":ok return passes the context through unchanged" do
      Hooks.register(:test_agent, :before_llm_call, fn _ctx -> :ok end)
      assert {:ok, %{a: 1}} = Hooks.fire(:test_agent, :before_llm_call, %{a: 1})
    end

    test "{:ok, ctx} return replaces the context" do
      Hooks.register(:test_agent, :before_llm_call, fn ctx ->
        {:ok, Map.put(ctx, :touched, true)}
      end)

      assert {:ok, %{a: 1, touched: true}} =
               Hooks.fire(:test_agent, :before_llm_call, %{a: 1})
    end

    test "{:halt, reason} return halts the chain" do
      Hooks.register(:test_agent, :before_llm_call, fn _ctx -> {:halt, :stop_now} end)
      assert {:halt, :stop_now} = Hooks.fire(:test_agent, :before_llm_call, %{a: 1})
    end
  end

  describe "fire/3 with multiple hooks" do
    test "callbacks run in registration order, threading context" do
      parent = self()

      Hooks.register(:test_agent, :before_llm_call, fn ctx ->
        send(parent, {:hook, 1, ctx})
        {:ok, Map.put(ctx, :n, 1)}
      end)

      Hooks.register(:test_agent, :before_llm_call, fn ctx ->
        send(parent, {:hook, 2, ctx})
        {:ok, Map.put(ctx, :n, 2)}
      end)

      assert {:ok, %{n: 2}} = Hooks.fire(:test_agent, :before_llm_call, %{})

      assert_received {:hook, 1, %{}}
      assert_received {:hook, 2, %{n: 1}}
    end

    test "halt stops subsequent callbacks from running" do
      parent = self()

      Hooks.register(:test_agent, :before_llm_call, fn _ctx -> {:halt, :stop} end)

      Hooks.register(:test_agent, :before_llm_call, fn _ctx ->
        send(parent, :should_not_run)
        :ok
      end)

      assert {:halt, :stop} = Hooks.fire(:test_agent, :before_llm_call, %{})
      refute_received :should_not_run
    end
  end

  describe "global hooks" do
    test "fire alongside agent-specific ones" do
      parent = self()

      Hooks.register(:test_agent, :before_tool_call, fn ctx ->
        send(parent, :scoped)
        {:ok, ctx}
      end)

      Hooks.register_global(:before_tool_call, fn ctx ->
        send(parent, :global)
        {:ok, ctx}
      end)

      assert {:ok, _} = Hooks.fire(:test_agent, :before_tool_call, %{})
      assert_received :scoped
      assert_received :global
    end

    test "global hooks fire even when no agent-specific hook is registered" do
      parent = self()
      Hooks.register_global(:on_error, fn _ -> send(parent, :got) end)
      Hooks.fire(:other_agent, :on_error, %{})
      assert_received :got
    end
  end

  describe "crash isolation" do
    test "a callback that raises is logged and treated as :ok" do
      Hooks.register(:test_agent, :before_llm_call, fn _ctx -> raise "boom" end)
      Hooks.register(:test_agent, :before_llm_call, fn ctx -> {:ok, Map.put(ctx, :ran, true)} end)

      assert {:ok, %{ran: true}} = Hooks.fire(:test_agent, :before_llm_call, %{})
    end

    test "a callback that throws is logged and treated as :ok" do
      Hooks.register(:test_agent, :before_llm_call, fn _ctx -> throw(:weird) end)
      Hooks.register(:test_agent, :before_llm_call, fn ctx -> {:ok, Map.put(ctx, :ran, true)} end)

      assert {:ok, %{ran: true}} = Hooks.fire(:test_agent, :before_llm_call, %{})
    end

    test "a callback returning garbage is logged and treated as :ok" do
      Hooks.register(:test_agent, :before_llm_call, fn _ctx -> :nonsense end)
      assert {:ok, %{a: 1}} = Hooks.fire(:test_agent, :before_llm_call, %{a: 1})
    end
  end

  describe "process-link cleanup" do
    test "registrations are removed when the registering process exits" do
      parent = self()

      task =
        Task.async(fn ->
          Hooks.register(:test_agent, :before_llm_call, fn _ -> :ok end)
          send(parent, :registered)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :registered
      send(task.pid, :stop)
      Task.await(task)

      # After the task exits, the registration is gone — fire returns the
      # unchanged context with no callback running.
      assert {:ok, %{a: 1}} = Hooks.fire(:test_agent, :before_llm_call, %{a: 1})
    end
  end

  describe "validation" do
    test "register raises for unknown hook names" do
      assert_raise FunctionClauseError, fn ->
        Hooks.register(:test_agent, :not_a_hook, fn _ -> :ok end)
      end
    end

    test "register raises for non-arity-1 callbacks" do
      assert_raise FunctionClauseError, fn ->
        Hooks.register(:test_agent, :before_llm_call, fn -> :ok end)
      end
    end

    test "fire raises for unknown hook names" do
      assert_raise FunctionClauseError, fn ->
        Hooks.fire(:test_agent, :not_a_hook, %{})
      end
    end
  end
end
