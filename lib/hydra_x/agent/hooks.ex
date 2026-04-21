defmodule HydraX.Agent.Hooks do
  @moduledoc """
  Lifecycle hook registry for `HydraX.Agent.Channel` and friends.

  Hooks are registered against a specific `agent_id` (or globally) for one
  of the events listed in `hooks/0`. When a hook fires, every registered
  callback is invoked in turn with a `context` map; each callback can:

    * return `:ok` — context unchanged, continue with the next callback
    * return `{:ok, new_context}` — replace the context, continue
    * return `{:halt, reason}` — stop fan-out, fire/3 returns `{:halt, reason}`

  Callbacks that raise are caught and logged but do not halt the chain — a
  buggy hook should never break an agent's main loop.

  Registration is process-tied via `Registry`: when the registering process
  dies, its hooks are cleaned up automatically. This is exactly what we want
  for per-conversation channel processes.

  ## Observer hooks

  `after_llm_call`, `after_tool_call`, `after_compaction`, `after_session_start`,
  and `on_error` are **observer-only**: their return value (including
  `{:halt, reason}`) is discarded by the calling site. Use them for logging,
  metrics, and side effects, not for control-flow decisions. Use the
  corresponding `before_*` hook if you need to halt or modify behaviour.

  ## Session + streaming hooks

  `before_session_start` fires from `HydraX.Agent.Channel.init/1` before the
  channel settles into its initial state; halting prevents the channel from
  coming up. `after_session_start` fires once the state is ready. The
  `before_response_stream` hook fires per streamed chunk and can rewrite or
  drop the delta before it's broadcast to subscribers.
  """

  require Logger

  @registry HydraX.Agent.HookRegistry

  @hooks ~w(
    before_session_start
    after_session_start
    before_llm_call
    after_llm_call
    before_tool_call
    after_tool_call
    before_compaction
    after_compaction
    before_response_stream
    on_steering_message
    on_error
  )a

  @type hook ::
          :before_session_start
          | :after_session_start
          | :before_llm_call
          | :after_llm_call
          | :before_tool_call
          | :after_tool_call
          | :before_compaction
          | :after_compaction
          | :before_response_stream
          | :on_steering_message
          | :on_error

  @type callback :: (map() -> :ok | {:ok, map()} | {:halt, term()})
  @type fire_result :: {:ok, map()} | {:halt, term()}

  @doc "Returns the list of supported hook names."
  @spec hooks() :: [hook()]
  def hooks, do: @hooks

  @doc "Returns the registry name (used internally and by the supervisor)."
  def registry, do: @registry

  @doc """
  Register a callback for a specific agent's hook. The registration is
  scoped to the calling process and cleaned up when it exits.
  """
  @spec register(term(), hook(), callback()) :: {:ok, pid()} | {:error, term()}
  def register(agent_id, hook, callback)
      when hook in @hooks and is_function(callback, 1) do
    Registry.register(@registry, {agent_id, hook}, callback)
  end

  @doc """
  Register a global callback that fires for every agent on a given hook.
  Use sparingly — global hooks see every agent's traffic.
  """
  @spec register_global(hook(), callback()) :: {:ok, pid()} | {:error, term()}
  def register_global(hook, callback) when hook in @hooks and is_function(callback, 1) do
    Registry.register(@registry, {:global, hook}, callback)
  end

  @doc """
  Unregister all callbacks the calling process has set for the given key.
  Mostly useful in tests; production code relies on process-exit cleanup.
  """
  def unregister(agent_id, hook) when hook in @hooks do
    Registry.unregister(@registry, {agent_id, hook})
  end

  def unregister_global(hook) when hook in @hooks do
    Registry.unregister(@registry, {:global, hook})
  end

  @doc """
  Fire a hook. Runs every callback registered against `{agent_id, hook}` and
  every callback registered against `{:global, hook}`, threading `context`
  through them. Returns `{:ok, final_context}` or `{:halt, reason}`.

  When no hooks are registered, this is a single Registry lookup plus a
  no-op reduce — safe to call from hot paths.
  """
  @spec fire(term(), hook(), map()) :: fire_result()
  def fire(agent_id, hook, context) when hook in @hooks and is_map(context) do
    callbacks =
      Registry.lookup(@registry, {agent_id, hook}) ++
        Registry.lookup(@registry, {:global, hook})

    case callbacks do
      [] ->
        {:ok, context}

      _ ->
        run_chain(callbacks, hook, agent_id, context)
    end
  end

  defp run_chain(callbacks, hook, agent_id, context) do
    Enum.reduce_while(callbacks, {:ok, context}, fn {_pid, callback}, {:ok, ctx} ->
      case run_callback(callback, ctx, hook, agent_id) do
        :ok -> {:cont, {:ok, ctx}}
        {:ok, new_ctx} when is_map(new_ctx) -> {:cont, {:ok, new_ctx}}
        {:halt, reason} -> {:halt, {:halt, reason}}
        other -> {:cont, log_bad_return(other, hook, agent_id, ctx)}
      end
    end)
  end

  defp run_callback(callback, ctx, hook, agent_id) do
    callback.(ctx)
  rescue
    e ->
      Logger.warning(
        "agent hook callback crashed " <>
          "(agent_id=#{inspect(agent_id)}, hook=#{hook}, error=#{Exception.message(e)})"
      )

      :ok
  catch
    kind, reason ->
      Logger.warning(
        "agent hook callback threw " <>
          "(agent_id=#{inspect(agent_id)}, hook=#{hook}, kind=#{kind}, reason=#{inspect(reason)})"
      )

      :ok
  end

  defp log_bad_return(value, hook, agent_id, ctx) do
    Logger.warning(
      "agent hook returned unexpected value " <>
        "(agent_id=#{inspect(agent_id)}, hook=#{hook}, value=#{inspect(value)}); " <>
        "treating as :ok"
    )

    {:ok, ctx}
  end
end
