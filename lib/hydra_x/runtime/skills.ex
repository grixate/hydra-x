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

  def skill_prompt_context(agent_id) do
    agent = Repo.get!(AgentProfile, agent_id)

    enabled_skills(agent_id)
    |> Enum.map(fn skill ->
      relative_path =
        get_in(skill.metadata || %{}, ["relative_path"]) ||
          Path.relative_to(skill.path, agent.workspace_root)

      description =
        skill.description
        |> Helpers.blank_to_nil()
        |> Kernel.||("No description provided.")

      "- #{skill.name} (`#{skill.slug}`): #{description} [#{relative_path}]"
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
        relative_dir =
          path
          |> Path.dirname()
          |> Path.relative_to(skills_root)

        %{
          slug:
            relative_dir
            |> String.replace("/", "-")
            |> String.replace("_", "-"),
          name: skill_name(relative_dir, body),
          path: path,
          description: skill_description(body),
          source: "workspace",
          metadata: %{
            "relative_path" => Path.relative_to(path, skills_root |> Path.dirname()),
            "directory" => relative_dir
          }
        }

      {:error, _reason} ->
        nil
    end
  end

  defp skill_name(relative_dir, body) do
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

  defp maybe_filter_agent(query, nil), do: query
  defp maybe_filter_agent(query, agent_id), do: where(query, [skill], skill.agent_id == ^agent_id)

  defp maybe_filter_enabled(query, nil), do: query
  defp maybe_filter_enabled(query, enabled), do: where(query, [skill], skill.enabled == ^enabled)
end
