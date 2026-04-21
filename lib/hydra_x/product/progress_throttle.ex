defmodule HydraX.Product.ProgressThrottle do
  @moduledoc """
  Stream A4.1 — rate-limit `agent_task.progress` broadcasts.

  During a bulk run (e.g., Researcher processing 50 sources), the
  progress update rate can exceed 100 events/second/project. Each event
  fans out to every subscribed ChatDock / CC Zone 2 / bell. Without a
  throttle the front-end overflows its render budget.

  The DB row still reflects every update; only the **channel broadcast**
  is gated. Subscribers receive at most one `agent_task.progress` event
  per task per `@min_interval_ms` window.

  Terminal state transitions (`state_changed`) are never throttled —
  those go straight through via a different event name.
  """

  use GenServer

  @table :hx_progress_throttle
  @min_interval_ms 200

  ## Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Returns `:allow` if enough time has elapsed since the last broadcast
  for this task, `:deny` otherwise. Side effect: stamps the table so the
  next call within the window is denied.

  Uses `:ets.insert_new` + `:ets.select_replace` so two concurrent
  callers targeting the same task_id can't both race past the check
  and both pass.
  """
  @spec check(integer()) :: :allow | :deny
  def check(task_id) when is_integer(task_id) do
    now = System.monotonic_time(:millisecond)

    if :ets.insert_new(@table, {task_id, now}) do
      :allow
    else
      # Row exists; only replace if the existing `last` is older than the
      # cutoff. `select_replace` is atomic per-key.
      cutoff = now - @min_interval_ms

      match = [
        {
          {:"$1", :"$2"},
          [{:andalso, {:==, :"$1", task_id}, {:"=<", :"$2", cutoff}}],
          [{{:"$1", now}}]
        }
      ]

      case :ets.select_replace(@table, match) do
        1 -> :allow
        _ -> :deny
      end
    end
  rescue
    ArgumentError ->
      # Table not yet initialised (e.g. in tests that bypass the
      # application supervisor). Fail open.
      :allow
  end

  @doc "Clear a task's throttle bucket (called on terminal transition)."
  def reset(task_id) when is_integer(task_id) do
    try do
      :ets.delete(@table, task_id)
    rescue
      ArgumentError -> :ok
    end
  end

  ## GenServer

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end
end
