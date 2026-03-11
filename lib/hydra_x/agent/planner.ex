defmodule HydraX.Agent.Planner do
  @moduledoc false

  def build(conversation, coalesced_turns, tools, skills \\ []) do
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
    skill_hints = suggest_skills(latest_message, skills)

    %{
      "channel" => conversation.channel,
      "mode" => if(available_tools == [], do: "direct", else: "tool_capable"),
      "latest_message" => latest_message,
      "coalesced_turn_ids" => Enum.map(coalesced_turns, & &1.id),
      "available_tools" => available_tools,
      "skill_hints" => skill_hints,
      "suggested_tools" => suggested_tools,
      "steps" => plan_steps(suggested_tools, skill_hints)
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

  defp suggest_skills(message, skills) when is_binary(message) do
    lower = String.downcase(message)

    skills
    |> Enum.filter(&skill_match?(&1, lower))
    |> Enum.map(fn skill ->
      %{
        "slug" => skill.slug,
        "name" => skill.name,
        "reason" => skill_reason(skill)
      }
    end)
  end

  defp suggest_skills(_message, _skills), do: []

  defp plan_steps([], skill_hints) do
    skill_steps(skill_hints) ++
      [
        step(%{
          "id" => "provider-final",
          "kind" => "provider",
          "label" => "Generate a direct model response",
          "status" => "pending"
        })
      ]
  end

  defp plan_steps(suggested_tools, skill_hints) do
    skill_steps(skill_hints) ++
      (Enum.with_index(suggested_tools, 1)
       |> Enum.map(fn {tool, index} ->
         step(%{
            "id" => "tool-#{index}-#{tool["name"]}",
            "kind" => step_kind_for_tool(tool["name"]),
            "name" => tool["name"],
            "label" => step_label_for_tool(tool["name"]),
            "reason" => tool["reason"],
            "status" => "pending"
          })
        end)) ++
      [
        step(%{
          "id" => "provider-final",
          "kind" => "provider",
          "label" => "Synthesize the final response from tool results",
          "status" => "pending"
        })
      ]
  end

  defp skill_steps([]), do: []

  defp skill_steps(skill_hints) do
    [
      step(%{
        "id" => "skill-context",
        "kind" => "skill",
        "label" => "Apply enabled skill guidance",
        "status" => "completed",
        "summary" => "Matched #{length(skill_hints)} skill hints",
        "output_excerpt" =>
          skill_hints
          |> Enum.map(&(&1["name"] || &1["slug"] || "skill"))
          |> Enum.join(", ")
      })
    ]
  end

  defp step(attrs) do
    attrs
    |> Map.put_new("attempt_count", 0)
    |> Map.put_new("executor", "channel")
  end

  defp step_kind_for_tool("memory_recall"), do: "memory"
  defp step_kind_for_tool("memory_save"), do: "memory"
  defp step_kind_for_tool("mcp_catalog"), do: "integration"
  defp step_kind_for_tool("mcp_inspect"), do: "integration"
  defp step_kind_for_tool("mcp_invoke"), do: "integration"
  defp step_kind_for_tool("mcp_probe"), do: "integration"
  defp step_kind_for_tool("skill_inspect"), do: "skill"
  defp step_kind_for_tool("browser_automation"), do: "browser"
  defp step_kind_for_tool("web_search"), do: "search"
  defp step_kind_for_tool("http_fetch"), do: "fetch"
  defp step_kind_for_tool("shell_command"), do: "shell"
  defp step_kind_for_tool("workspace_read"), do: "workspace"
  defp step_kind_for_tool("workspace_list"), do: "workspace"
  defp step_kind_for_tool("workspace_write"), do: "workspace"
  defp step_kind_for_tool("workspace_patch"), do: "workspace"
  defp step_kind_for_tool(_tool_name), do: "tool"

  defp step_label_for_tool("memory_recall"), do: "Recall relevant memory"
  defp step_label_for_tool("memory_save"), do: "Persist new memory"
  defp step_label_for_tool("mcp_catalog"), do: "Discover MCP actions"
  defp step_label_for_tool("mcp_inspect"), do: "Inspect MCP integrations"
  defp step_label_for_tool("mcp_invoke"), do: "Invoke MCP action"
  defp step_label_for_tool("mcp_probe"), do: "Probe MCP integrations"
  defp step_label_for_tool("skill_inspect"), do: "Inspect enabled skills"
  defp step_label_for_tool("browser_automation"), do: "Inspect web page state"
  defp step_label_for_tool("web_search"), do: "Search the public web"
  defp step_label_for_tool("http_fetch"), do: "Fetch a specific URL"
  defp step_label_for_tool("shell_command"), do: "Run an allowlisted shell command"
  defp step_label_for_tool("workspace_read"), do: "Read a workspace file"
  defp step_label_for_tool("workspace_list"), do: "List workspace files"
  defp step_label_for_tool("workspace_write"), do: "Write a workspace file"
  defp step_label_for_tool("workspace_patch"), do: "Patch a workspace file"
  defp step_label_for_tool(tool_name), do: tool_name

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

  defp tool_reason("mcp_catalog", message) do
    if contains_any?(message, ["mcp actions", "integration actions", "available actions", "what can mcp", "what can the integration"]) do
      "discover actions exposed by enabled MCP integrations"
    end
  end

  defp tool_reason("mcp_inspect", message) do
    if contains_any?(message, ["mcp", "integration", "tool server", "server health"]),
      do: "inspect configured MCP integrations"
  end

  defp tool_reason("mcp_invoke", message) do
    if contains_any?(message, ["invoke mcp", "call mcp", "run integration action", "use integration"]),
      do: "invoke an enabled MCP integration action"
  end

  defp tool_reason("mcp_probe", message) do
    if contains_any?(message, [
         "probe mcp",
         "verify integration",
         "test integration",
         "integration health"
       ]),
       do: "probe enabled MCP integrations"
  end

  defp tool_reason("skill_inspect", message) do
    if contains_any?(message, ["skill", "workflow", "playbook", "checklist"]),
      do: "inspect enabled workspace skills"
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

  defp skill_match?(skill, message) do
    tags = get_in(skill.metadata || %{}, ["tags"]) || []
    summary = get_in(skill.metadata || %{}, ["summary"]) || skill.description || ""

    haystack =
      [skill.name, skill.slug, summary | tags]
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.downcase/1)

    Enum.any?(haystack, fn value ->
      value != "" and (String.contains?(message, value) or overlap?(message, value))
    end)
  end

  defp skill_reason(skill) do
    tags = get_in(skill.metadata || %{}, ["tags"]) || []

    summary =
      get_in(skill.metadata || %{}, ["summary"]) || skill.description ||
        "relevant workspace skill"

    case tags do
      [] -> summary
      _ -> "#{summary} [tags: #{Enum.join(tags, ", ")}]"
    end
  end

  defp overlap?(message, value) do
    value
    |> String.split(~r/[\s\-_\/]+/, trim: true)
    |> Enum.any?(fn token -> String.length(token) > 3 and String.contains?(message, token) end)
  end

  defp contains_any?(message, needles) do
    Enum.any?(needles, &String.contains?(message, &1))
  end
end
