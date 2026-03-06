defmodule HydraX.Agent.Branch do
  @moduledoc false
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def run(agent_id, conversation_id, messages) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        HydraX.Agent.branch_supervisor(agent_id),
        {__MODULE__, %{agent_id: agent_id, conversation_id: conversation_id, messages: messages}}
      )

    GenServer.call(pid, :run, 15_000)
  end

  @impl true
  def init(args), do: {:ok, args}

  @impl true
  def handle_call(:run, _from, %{messages: messages} = state) do
    text = Enum.map_join(messages, "\n", & &1.content)

    analysis = %{
      intent: detect_intent(text),
      should_save_memory: String.match?(text, ~r/\bremember\b/i),
      should_recall_memory:
        String.match?(text, ~r/\brecall\b|\bremember about\b|\bwhat do you remember\b/i),
      should_read_workspace:
        String.match?(text, ~r/\b(read|show|open)\s+(?:the\s+)?(?:file|workspace)\b/i),
      workspace_path: extract_workspace_path(text),
      should_fetch_url:
        String.match?(text, ~r/\b(fetch|download|open)\b/i) and
          String.match?(text, ~r/https?:\/\//i),
      url: extract_url(text),
      should_run_shell: String.match?(text, ~r/\b(?:run|execute)\s+(?:shell\s+command\s+)?\S+/i),
      shell_command: extract_shell_command(text),
      memory_type: detect_memory_type(text),
      query: extract_query(text),
      summary: String.slice(String.trim(text), 0, 280)
    }

    {:stop, :normal, analysis, state}
  end

  defp detect_intent(text) do
    cond do
      String.match?(text, ~r/\bremember\b/i) -> "memory_write"
      String.match?(text, ~r/\brecall\b|\bwhat do you remember\b/i) -> "memory_read"
      true -> "conversation"
    end
  end

  defp detect_memory_type(text) do
    cond do
      String.match?(text, ~r/\bprefer|preference\b/i) -> "Preference"
      String.match?(text, ~r/\bdecide|decision\b/i) -> "Decision"
      String.match?(text, ~r/\bgoal\b/i) -> "Goal"
      String.match?(text, ~r/\btodo\b/i) -> "Todo"
      true -> "Fact"
    end
  end

  defp extract_query(text) do
    text
    |> String.replace(~r/\bremember\b/i, "")
    |> String.replace(~r/\brecall\b/i, "")
    |> String.trim()
  end

  defp extract_workspace_path(text) do
    case Regex.run(
           ~r/\b(?:read|show|open)\s+(?:the\s+)?(?:file|workspace)\s+([A-Za-z0-9_\.\/-]+)/i,
           text
         ) do
      [_, path] -> path
      _ -> nil
    end
  end

  defp extract_url(text) do
    case Regex.run(~r/(https?:\/\/[^\s]+)/i, text) do
      [url] -> String.trim_trailing(url, ".")
      _ -> nil
    end
  end

  defp extract_shell_command(text) do
    case Regex.run(~r/\b(?:run|execute)\s+(?:shell\s+command\s+)?(.+)$/i, text) do
      [_, command] ->
        command
        |> String.trim()
        |> String.trim_trailing(".")

      _ ->
        nil
    end
  end
end
