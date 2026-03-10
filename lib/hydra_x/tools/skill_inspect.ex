defmodule HydraX.Tools.SkillInspect do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "skill_inspect"

  @impl true
  def description, do: "Inspect enabled workspace skills for the current agent"

  @impl true
  def safety_classification, do: "skill_read"

  @impl true
  def tool_schema do
    %{
      name: "skill_inspect",
      description:
        "Inspect enabled skills for the current agent, including summaries and tags. Use this when you need to understand available workspace workflows before choosing tools or a plan.",
      input_schema: %{
        type: "object",
        properties: %{
          only_enabled: %{
            type: "boolean",
            description: "Only include enabled skills (default: true)"
          },
          tag: %{
            type: "string",
            description: "Optional tag filter"
          }
        }
      }
    }
  end

  @impl true
  def execute(params, _context) do
    agent_id = params[:agent_id] || params["agent_id"]
    only_enabled = truthy?(params[:only_enabled] || params["only_enabled"], true)
    tag_filter = normalize_tag(params[:tag] || params["tag"])

    skills =
      HydraX.Runtime.list_skills(agent_id: agent_id)
      |> Enum.filter(fn skill -> not only_enabled or skill.enabled end)
      |> Enum.filter(fn skill ->
        is_nil(tag_filter) or Enum.member?(skill_tags(skill), tag_filter)
      end)
      |> Enum.map(fn skill ->
        %{
          id: skill.id,
          slug: skill.slug,
          name: skill.name,
          enabled: skill.enabled,
          description: skill.description,
          version: get_in(skill.metadata || %{}, ["version"]),
          tags: skill_tags(skill),
          tools: get_in(skill.metadata || %{}, ["tools"]) || [],
          channels: get_in(skill.metadata || %{}, ["channels"]) || [],
          requires: get_in(skill.metadata || %{}, ["requires"]) || [],
          summary: get_in(skill.metadata || %{}, ["summary"]),
          path: get_in(skill.metadata || %{}, ["relative_path"]) || skill.path
        }
      end)

    {:ok,
     %{
       agent_id: agent_id,
       count: length(skills),
       skills: skills
     }}
  end

  @impl true
  def result_summary(%{count: count}), do: "inspected #{count} skills"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp skill_tags(skill) do
    get_in(skill.metadata || %{}, ["tags"]) || []
  end

  defp normalize_tag(nil), do: nil
  defp normalize_tag(""), do: nil
  defp normalize_tag(tag), do: String.downcase(to_string(tag))

  defp truthy?(nil, default), do: default
  defp truthy?(value, _default) when is_boolean(value), do: value
  defp truthy?(value, _default) when value in ["true", "1", 1], do: true
  defp truthy?(value, _default) when value in ["false", "0", 0], do: false
  defp truthy?(_value, default), do: default
end
