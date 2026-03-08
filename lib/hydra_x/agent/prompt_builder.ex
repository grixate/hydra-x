defmodule HydraX.Agent.PromptBuilder do
  @moduledoc false

  alias HydraX.Workspace
  alias HydraX.Tool.Registry

  def build(agent, history, bulletin, summary, opts \\ %{}) do
    workspace = Workspace.load_context(agent.workspace_root)
    tool_policy = Map.get(opts, :tool_policy, %{})

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

    tools = Registry.available_schemas(tool_policy)

    %{messages: messages, tools: tools, bulletin: bulletin}
  end

  @doc """
  Append tool results to a message list in the Anthropic tool-result format.
  Tool results go as a user message with tool_result content blocks.
  """
  def append_tool_results(messages, tool_results) when is_list(tool_results) do
    content_blocks =
      Enum.map(tool_results, fn result ->
        %{
          type: "tool_result",
          tool_use_id: result.tool_use_id,
          content: Jason.encode!(result.result),
          is_error: result[:is_error] || false
        }
      end)

    messages ++ [%{role: "user", content: content_blocks}]
  end

  @doc """
  Append an assistant message with tool_use blocks to the message list.
  This preserves the LLM's tool invocations in the conversation history.
  """
  def append_assistant_tool_use(messages, response) do
    content_blocks = build_assistant_content_blocks(response)
    messages ++ [%{role: "assistant", content: content_blocks}]
  end

  defp build_assistant_content_blocks(%{content: text, tool_calls: tool_calls}) do
    text_blocks =
      if text not in [nil, ""],
        do: [%{type: "text", text: text}],
        else: []

    tool_blocks =
      (tool_calls || [])
      |> Enum.map(fn call ->
        %{
          type: "tool_use",
          id: call.id,
          name: call.name,
          input: call.arguments
        }
      end)

    text_blocks ++ tool_blocks
  end

  defp history_messages(turns) do
    turns
    |> Enum.take(-10)
    |> Enum.map(fn turn -> %{role: turn.role, content: turn.content} end)
  end
end
