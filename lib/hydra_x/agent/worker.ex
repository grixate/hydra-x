defmodule HydraX.Agent.Worker do
  @moduledoc false
  @behaviour :gen_statem

  alias HydraX.Runtime
  alias HydraX.Safety
  alias HydraX.Tools.{HttpFetch, MemoryRecall, MemorySave, ShellCommand, WorkspaceRead}

  def start_link(args) do
    :gen_statem.start_link(__MODULE__, args, [])
  end

  def child_spec(args) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary
    }
  end

  def run(agent_id, conversation, analysis, messages) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        HydraX.Agent.worker_supervisor(agent_id),
        {__MODULE__, %{conversation: conversation, analysis: analysis, messages: messages}}
      )

    :gen_statem.call(pid, :run, 15_000)
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(args) do
    {:ok, :ready, args}
  end

  @impl true
  def handle_event(
        {:call, from},
        :run,
        :ready,
        %{conversation: conversation, analysis: analysis, messages: messages} = data
      ) do
    full_text = Enum.map_join(messages, "\n", & &1.content)
    agent = Runtime.get_agent!(conversation.agent_id)
    context = %{workspace_root: agent.workspace_root}

    results =
      []
      |> maybe_save_memory(analysis, conversation, full_text)
      |> maybe_recall_memory(analysis, conversation)
      |> maybe_read_workspace(analysis, conversation, context)
      |> maybe_fetch_url(analysis, conversation, context)
      |> maybe_run_shell(analysis, conversation, context)

    {:stop_and_reply, :normal, [{:reply, from, results}], data}
  end

  def handle_event(_type, _event, _state, data), do: {:keep_state, data}

  defp maybe_save_memory(results, %{should_save_memory: false}, _conversation, _text), do: results

  defp maybe_save_memory(results, analysis, conversation, text) do
    {:ok, result} =
      MemorySave.execute(
        %{
          agent_id: conversation.agent_id,
          conversation_id: conversation.id,
          type: analysis.memory_type,
          content: String.trim(text)
        },
        %{}
      )

    [
      %{tool: MemorySave.name(), type: result.type, content: result.content, id: result.id}
      | results
    ]
  end

  defp maybe_recall_memory(results, %{should_recall_memory: false}, _conversation), do: results

  defp maybe_recall_memory(results, analysis, conversation) do
    {:ok, %{results: memories}} =
      MemoryRecall.execute(
        %{agent_id: conversation.agent_id, query: analysis.query, limit: 5},
        %{}
      )

    [%{tool: MemoryRecall.name(), results: memories} | results]
  end

  defp maybe_read_workspace(results, %{should_read_workspace: false}, _conversation, _context),
    do: results

  defp maybe_read_workspace(results, %{workspace_path: nil}, _conversation, _context), do: results

  defp maybe_read_workspace(results, analysis, conversation, context) do
    case WorkspaceRead.execute(%{path: analysis.workspace_path}, context) do
      {:ok, result} ->
        [%{tool: WorkspaceRead.name(), path: result.path, excerpt: result.excerpt} | results]

      {:error, reason} ->
        log_tool_warning(
          conversation,
          WorkspaceRead.name(),
          %{path: analysis.workspace_path},
          reason
        )

        [
          %{tool: WorkspaceRead.name(), path: analysis.workspace_path, error: inspect(reason)}
          | results
        ]
    end
  end

  defp maybe_fetch_url(results, %{should_fetch_url: false}, _conversation, _context), do: results
  defp maybe_fetch_url(results, %{url: nil}, _conversation, _context), do: results

  defp maybe_fetch_url(results, analysis, conversation, context) do
    case HttpFetch.execute(%{url: analysis.url}, context) do
      {:ok, result} ->
        [
          %{
            tool: HttpFetch.name(),
            url: result.url,
            excerpt: result.excerpt,
            status: result.status
          }
          | results
        ]

      {:error, reason} ->
        log_tool_warning(conversation, HttpFetch.name(), %{url: analysis.url}, reason)
        [%{tool: HttpFetch.name(), url: analysis.url, error: inspect(reason)} | results]
    end
  end

  defp maybe_run_shell(results, %{should_run_shell: false}, _conversation, _context), do: results
  defp maybe_run_shell(results, %{shell_command: nil}, _conversation, _context), do: results

  defp maybe_run_shell(results, analysis, conversation, context) do
    case ShellCommand.execute(%{command: analysis.shell_command}, context) do
      {:ok, result} ->
        [
          %{
            tool: ShellCommand.name(),
            command: result.command,
            output: result.output,
            exit_status: result.exit_status
          }
          | results
        ]

      {:error, reason} ->
        log_tool_warning(
          conversation,
          ShellCommand.name(),
          %{command: analysis.shell_command},
          reason
        )

        [
          %{tool: ShellCommand.name(), command: analysis.shell_command, error: inspect(reason)}
          | results
        ]
    end
  end

  defp log_tool_warning(conversation, tool_name, params, reason) do
    Safety.log_event(%{
      agent_id: conversation.agent_id,
      conversation_id: conversation.id,
      category: "tool",
      level: "warn",
      message: "#{tool_name} blocked or failed",
      metadata: %{
        tool: tool_name,
        params: params,
        reason: inspect(reason)
      }
    })
  end
end
