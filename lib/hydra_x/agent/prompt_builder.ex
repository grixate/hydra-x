defmodule HydraX.Agent.PromptBuilder do
  @moduledoc false

  alias HydraX.Workspace

  def build(agent, history, bulletin, summary, tool_results) do
    workspace = Workspace.load_context(agent.workspace_root)

    system_parts =
      [
        workspace["SOUL.md"],
        workspace["IDENTITY.md"],
        workspace["USER.md"],
        workspace["TOOLS.md"],
        if(bulletin not in [nil, ""], do: "## Bulletin\n\n#{bulletin}"),
        if(summary not in [nil, ""], do: "## Conversation Summary\n\n#{summary}")
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    messages =
      [%{role: "system", content: Enum.join(system_parts, "\n\n")}]
      |> Kernel.++(history_messages(history))
      |> Kernel.++(tool_messages(tool_results))

    %{messages: messages, bulletin: bulletin, tool_results: tool_results}
  end

  defp history_messages(turns) do
    turns
    |> Enum.take(-10)
    |> Enum.map(fn turn -> %{role: turn.role, content: turn.content} end)
  end

  defp tool_messages(tool_results) do
    Enum.map(tool_results, fn result ->
      %{role: "system", content: "Tool #{result.tool}: #{Jason.encode!(result)}"}
    end)
  end
end
