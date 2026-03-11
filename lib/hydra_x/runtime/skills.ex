defmodule HydraX.Runtime.Skills do
  @moduledoc """
  Discovers workspace skills and manages per-agent enabled state.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Helpers, SkillInstall}

  def list_skills(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    enabled = Keyword.get(opts, :enabled)

    SkillInstall
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_enabled(enabled)
    |> order_by([skill], asc: skill.name, asc: skill.slug)
    |> Repo.all()
  end

  def list_skills_for_agent(agent_id), do: list_skills(agent_id: agent_id)
  def enabled_skills(agent_id), do: list_skills(agent_id: agent_id, enabled: true)
  def get_skill!(id), do: Repo.get!(SkillInstall, id)

  def skill_catalog(agent_id) when is_integer(agent_id) do
    list_skills(agent_id: agent_id)
    |> Enum.map(&catalog_entry/1)
  end

  def export_skill_catalog(agent_id, output_root) when is_integer(agent_id) and is_binary(output_root) do
    agent = Repo.get!(AgentProfile, agent_id)
    catalog = skill_catalog(agent.id)
    File.mkdir_p!(output_root)

    path = Path.join(output_root, "skills-#{agent.slug}.json")

    payload = %{
      generated_at: DateTime.utc_now(),
      agent: %{id: agent.id, slug: agent.slug, name: agent.name},
      count: length(catalog),
      skills: catalog
    }

    File.write!(path, Jason.encode_to_iodata!(payload, pretty: true))

    Helpers.audit_operator_action(
      "Exported skill catalog for #{agent.slug}",
      agent: agent,
      metadata: %{"path" => path, "skill_count" => length(catalog)}
    )

    {:ok, path}
  end

  def refresh_agent_skills(agent_id) when is_integer(agent_id) do
    agent = Repo.get!(AgentProfile, agent_id)
    discovered = discover_skills(agent.workspace_root)

    Repo.transaction(fn ->
      existing =
        SkillInstall
        |> where([skill], skill.agent_id == ^agent.id)
        |> Repo.all()
        |> Map.new(&{&1.slug, &1})

      kept_slugs =
        Enum.map(discovered, fn attrs ->
          record = Map.get(existing, attrs.slug, %SkillInstall{})

          enabled =
            existing |> Map.get(attrs.slug, %SkillInstall{enabled: true}) |> Map.get(:enabled)

          attrs =
            attrs
            |> Map.put(:agent_id, agent.id)
            |> Map.put(:enabled, enabled)

          {:ok, saved} =
            record
            |> SkillInstall.changeset(attrs)
            |> Repo.insert_or_update()

          saved.slug
        end)

      SkillInstall
      |> where([skill], skill.agent_id == ^agent.id and skill.slug not in ^kept_slugs)
      |> Repo.delete_all()

      list_skills_for_agent(agent.id)
    end)
    |> Helpers.unwrap_transaction()
    |> case do
      {:ok, skills} ->
        Helpers.audit_operator_action(
          "Refreshed skills for #{agent.slug}",
          agent: agent,
          metadata: %{"skill_count" => length(skills)}
        )

        {:ok, skills}

      other ->
        other
    end
  end

  def enable_skill!(id), do: set_enabled!(id, true)
  def disable_skill!(id), do: set_enabled!(id, false)

  def skill_prompt_context(agent_id), do: skill_prompt_context(agent_id, %{})

  def skill_prompt_context(agent_id, opts) do
    agent = Repo.get!(AgentProfile, agent_id)
    channel = Helpers.blank_to_nil(opts[:channel] || opts["channel"])
    tool_names = normalize_tool_names(opts[:tool_names] || opts["tool_names"] || [])

    enabled_skills(agent_id)
    |> Enum.filter(&skill_compatible?(&1, channel, tool_names))
    |> Enum.map(fn skill ->
      relative_path =
        get_in(skill.metadata || %{}, ["relative_path"]) ||
          Path.relative_to(skill.path, agent.workspace_root)

      description =
        skill.description
        |> Helpers.blank_to_nil()
        |> Kernel.||("No description provided.")

      metadata = skill.metadata || %{}
      version = Helpers.blank_to_nil(metadata["version"])
      tools = metadata["tools"] || []
      channels = metadata["channels"] || []
      requires = metadata["requires"] || []

      extras =
        []
        |> maybe_append_extra(version && "version #{version}")
        |> maybe_append_extra(if(tools == [], do: nil, else: "tools #{Enum.join(tools, ", ")}"))
        |> maybe_append_extra(
          if(channels == [], do: nil, else: "channels #{Enum.join(channels, ", ")}")
        )
        |> maybe_append_extra(
          if(requires == [], do: nil, else: "requires #{Enum.join(requires, ", ")}")
        )
        |> Enum.join("; ")

      "- #{skill.name} (`#{skill.slug}`): #{description} [#{relative_path}]#{if(extras == "", do: "", else: " (#{extras})")}"
    end)
    |> Enum.join("\n")
  end

  defp set_enabled!(id, enabled) do
    skill = get_skill!(id)

    {:ok, updated} =
      skill
      |> SkillInstall.changeset(%{enabled: enabled})
      |> Repo.update()

    agent = Repo.get!(AgentProfile, updated.agent_id)

    Helpers.audit_operator_action(
      "#{if(enabled, do: "Enabled", else: "Disabled")} skill #{updated.slug} for #{agent.slug}",
      agent: agent,
      metadata: %{"skill_id" => updated.id, "skill_slug" => updated.slug}
    )

    updated
  end

  defp discover_skills(workspace_root) do
    workspace_root
    |> Path.join("skills/**/SKILL.md")
    |> Path.wildcard()
    |> Enum.map(&build_skill_attrs(&1, Path.join(workspace_root, "skills")))
    |> Enum.reject(&is_nil/1)
  end

  defp build_skill_attrs(path, skills_root) do
    case File.read(path) do
      {:ok, body} ->
        {frontmatter, content_body} = parse_frontmatter(body)

        relative_dir =
          path
          |> Path.dirname()
          |> Path.relative_to(skills_root)

        tags = parse_tags(frontmatter["tags"])
        tools = parse_tags(frontmatter["tools"])
        channels = parse_tags(frontmatter["channels"])
        requires = parse_tags(frontmatter["requires"])
        summary = Helpers.blank_to_nil(frontmatter["summary"])
        version = Helpers.blank_to_nil(frontmatter["version"])

        %{
          slug:
            relative_dir
            |> String.replace("/", "-")
            |> String.replace("_", "-"),
          name: skill_name(relative_dir, content_body, frontmatter),
          path: path,
          description: summary || skill_description(content_body),
          source: "workspace",
          metadata: %{
            "relative_path" => Path.relative_to(path, skills_root |> Path.dirname()),
            "directory" => relative_dir,
            "summary" => summary,
            "tags" => tags,
            "version" => version,
            "tools" => tools,
            "channels" => channels,
            "requires" => requires
          }
        }

      {:error, _reason} ->
        nil
    end
  end

  defp skill_name(relative_dir, body, frontmatter) do
    case Helpers.blank_to_nil(frontmatter["name"]) do
      nil -> skill_name_from_body(relative_dir, body)
      value -> value
    end
  end

  defp skill_name_from_body(relative_dir, body) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.trim(line) do
        "#" <> rest -> String.trim(rest)
        _ -> nil
      end
    end)
    |> Kernel.||(
      relative_dir
      |> String.split("/")
      |> Enum.map(&String.replace(&1, "-", " "))
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" / ")
    )
  end

  defp skill_description(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "---"] or String.starts_with?(&1, "#")))
    |> List.first()
  end

  defp parse_frontmatter(body) do
    case String.split(body, "\n") do
      ["---" | rest] ->
        {metadata_lines, remaining} = Enum.split_while(rest, &(&1 != "---"))

        case remaining do
          ["---" | content_lines] ->
            metadata =
              metadata_lines
              |> Enum.map(&String.trim/1)
              |> Enum.reject(&(&1 == ""))
              |> Enum.reduce(%{}, fn line, acc ->
                case String.split(line, ":", parts: 2) do
                  [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
                  _ -> acc
                end
              end)

            {metadata, Enum.join(content_lines, "\n")}

          _ ->
            {%{}, body}
        end

      _ ->
        {%{}, body}
    end
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []

  defp parse_tags(csv) when is_binary(csv) do
    csv
    |> String.split([",", ";"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp catalog_entry(skill) do
    metadata = skill.metadata || %{}

    %{
      id: skill.id,
      slug: skill.slug,
      name: skill.name,
      enabled: skill.enabled,
      description: skill.description,
      path: skill.path,
      source: skill.source,
      version: metadata["version"],
      summary: metadata["summary"],
      tags: metadata["tags"] || [],
      tools: metadata["tools"] || [],
      channels: metadata["channels"] || [],
      requires: metadata["requires"] || [],
      relative_path: metadata["relative_path"] || skill.path
    }
  end

  defp maybe_append_extra(values, nil), do: values
  defp maybe_append_extra(values, ""), do: values
  defp maybe_append_extra(values, value), do: values ++ [value]

  defp normalize_tool_names(tool_names) when is_list(tool_names) do
    tool_names
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tool_names(_tool_names), do: []

  defp skill_compatible?(skill, channel, tool_names) do
    metadata = skill.metadata || %{}
    channels = metadata["channels"] || []
    tools = metadata["tools"] || []

    channel_ok? =
      cond do
        is_nil(channel) -> true
        channels == [] -> true
        true -> channel in channels
      end

    tool_ok? =
      cond do
        tools == [] -> true
        tool_names == [] -> true
        true -> Enum.any?(tools, &(&1 in tool_names))
      end

    channel_ok? and tool_ok?
  end

  defp maybe_filter_agent(query, nil), do: query
  defp maybe_filter_agent(query, agent_id), do: where(query, [skill], skill.agent_id == ^agent_id)

  defp maybe_filter_enabled(query, nil), do: query
  defp maybe_filter_enabled(query, enabled), do: where(query, [skill], skill.enabled == ^enabled)
end
