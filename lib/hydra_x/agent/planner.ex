defmodule HydraX.Agent.Planner do
  @moduledoc false

  def build(conversation, coalesced_turns, tools) do
    latest_message =
      coalesced_turns
      |> List.last()
      |> case do
        nil -> nil
        turn -> turn.content
      end

    available_tools =
      Enum.map(tools || [], fn tool ->
        %{
          "name" => tool.name,
          "description" => tool.description
        }
      end)

    suggested_tools = suggest_tools(latest_message, available_tools)

    %{
      "channel" => conversation.channel,
      "mode" => if(available_tools == [], do: "direct", else: "tool_capable"),
      "latest_message" => latest_message,
      "coalesced_turn_ids" => Enum.map(coalesced_turns, & &1.id),
      "available_tools" => available_tools,
      "suggested_tools" => suggested_tools,
      "steps" => plan_steps(suggested_tools)
    }
  end

  defp suggest_tools(message, available_tools) when is_binary(message) do
    lower = String.downcase(message)

    available_tools
    |> Enum.filter(fn tool -> tool_reason(tool["name"], lower) != nil end)
    |> Enum.map(fn tool ->
      %{
        "name" => tool["name"],
        "reason" => tool_reason(tool["name"], lower)
      }
    end)
  end

  defp suggest_tools(_message, _available_tools), do: []

  defp plan_steps([]) do
    [
      %{
        "kind" => "provider",
        "label" => "Generate a direct model response"
      }
    ]
  end

  defp plan_steps(suggested_tools) do
    Enum.map(suggested_tools, fn tool ->
      %{
        "kind" => "tool",
        "name" => tool["name"],
        "reason" => tool["reason"]
      }
    end) ++
      [
        %{
          "kind" => "provider",
          "label" => "Synthesize the final response from tool results"
        }
      ]
  end

  defp tool_reason("workspace_list", message) do
    if contains_any?(message, ["list", "directory", "folder"]),
      do: "inspect workspace structure"
  end

  defp tool_reason("workspace_read", message) do
    if contains_any?(message, [".md", ".ex", "read ", "show "]),
      do: "inspect a workspace file"
  end

  defp tool_reason("workspace_write", message) do
    if contains_any?(message, ["write", "create file"]),
      do: "write a workspace file"
  end

  defp tool_reason("workspace_patch", message) do
    if contains_any?(message, ["patch", "replace", "edit", "update file"]),
      do: "apply a targeted file edit"
  end

  defp tool_reason("http_fetch", message) do
    if contains_any?(message, ["http://", "https://", "fetch ", "open url"]),
      do: "fetch a specific URL"
  end

  defp tool_reason("web_search", message) do
    if contains_any?(message, ["search", "look up", "find online"]),
      do: "search the public web"
  end

  defp tool_reason("shell_command", message) do
    if contains_any?(message, ["shell", "command", "run "]),
      do: "run an allowlisted shell command"
  end

  defp tool_reason("memory_recall", message) do
    if contains_any?(message, ["remember", "recall", "what do you know"]),
      do: "recall saved memory"
  end

  defp tool_reason("memory_save", message) do
    if contains_any?(message, ["remember that", "save this", "note that"]),
      do: "save new memory"
  end

  defp tool_reason(_tool_name, _message), do: nil

  defp contains_any?(message, needles) do
    Enum.any?(needles, &String.contains?(message, &1))
  end
end
