defmodule HydraX.Ingest.Watcher do
  @moduledoc """
  Per-agent GenServer that watches the `workspace_root/ingest/` directory
  for file changes and triggers the ingest pipeline.

  Uses the `:file_system` library for cross-platform file watching.
  Debounces events by 500ms to avoid redundant processing.
  """

  use GenServer

  require Logger

  alias HydraX.Ingest.{Parser, Pipeline}

  @debounce_ms 500

  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    ingest_path = Keyword.fetch!(opts, :ingest_path)

    GenServer.start_link(__MODULE__, %{agent_id: agent_id, ingest_path: ingest_path},
      name: via_name(agent_id)
    )
  end

  def child_spec(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)

    %{
      id: {__MODULE__, agent_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def via_name(agent_id) do
    HydraX.ProcessRegistry.via({:ingest_watcher, agent_id})
  end

  @impl true
  def init(%{agent_id: agent_id, ingest_path: ingest_path}) do
    File.mkdir_p!(ingest_path)

    case FileSystem.start_link(dirs: [ingest_path]) do
      {:ok, watcher_pid} ->
        FileSystem.subscribe(watcher_pid)

        Logger.info("Ingest watcher started for agent #{agent_id}: #{ingest_path}")

        {:ok,
         %{
           agent_id: agent_id,
           ingest_path: ingest_path,
           watcher_pid: watcher_pid,
           pending: %{}
         }}

      {:error, reason} ->
        Logger.warning("Failed to start file watcher for agent #{agent_id}: #{inspect(reason)}")

        {:ok,
         %{
           agent_id: agent_id,
           ingest_path: ingest_path,
           watcher_pid: nil,
           pending: %{}
         }}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    filename = Path.basename(path)

    cond do
      # Ignore hidden files and non-supported formats
      String.starts_with?(filename, ".") ->
        {:noreply, state}

      not Parser.supported?(path) ->
        {:noreply, state}

      :deleted in events ->
        # File was deleted — archive entries after debounce
        state = schedule_debounce(state, path, :deleted)
        {:noreply, state}

      :modified in events or :created in events ->
        # File was created or modified — ingest after debounce
        state = schedule_debounce(state, path, :ingest)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("Ingest watcher stopped for agent #{state.agent_id}")
    {:noreply, state}
  end

  def handle_info({:debounced, path, action}, state) do
    state = %{state | pending: Map.delete(state.pending, path)}

    case action do
      :ingest ->
        Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
          Pipeline.ingest_file(state.agent_id, path)
        end)

      :deleted ->
        filename = Path.basename(path)

        Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
          Pipeline.archive_file(state.agent_id, filename)
        end)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{watcher_pid: pid}) when is_pid(pid) do
    GenServer.stop(pid)
  end

  def terminate(_reason, _state), do: :ok

  # -- Private --

  defp schedule_debounce(state, path, action) do
    # Cancel existing timer for this path
    case Map.get(state.pending, path) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref)
    end

    timer_ref = Process.send_after(self(), {:debounced, path, action}, @debounce_ms)
    %{state | pending: Map.put(state.pending, path, timer_ref)}
  end
end
