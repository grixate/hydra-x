defmodule HydraX.Runtime.SkillsProgressiveTest do
  use HydraX.DataCase, async: false

  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Skills, SkillInstall}
  alias HydraX.Tools.SkillLoad

  setup do
    suffix = System.unique_integer([:positive])

    tmp_ws = Path.join(System.tmp_dir!(), "hx_skill_test_#{suffix}")
    File.mkdir_p!(Path.join(tmp_ws, "skills"))

    agent =
      %AgentProfile{}
      |> AgentProfile.changeset(%{
        "name" => "skiller-#{suffix}",
        "slug" => "skiller-#{suffix}",
        "workspace_root" => tmp_ws
      })
      |> Repo.insert!()

    on_exit(fn -> File.rm_rf!(tmp_ws) end)

    {:ok, agent: agent, tmp_ws: tmp_ws, suffix: suffix}
  end

  defp insert_skill!(agent, slug_suffix, description, body) do
    slug = "test-skill-#{slug_suffix}"
    path = Path.join(agent.workspace_root, "skills/#{slug}.md")
    File.write!(path, body)

    %SkillInstall{}
    |> SkillInstall.changeset(%{
      agent_id: agent.id,
      slug: slug,
      name: "Test Skill #{slug_suffix}",
      path: path,
      description: description,
      enabled: true,
      source: "workspace",
      metadata: %{"relative_path" => "skills/#{slug}.md"}
    })
    |> Repo.insert!()
  end

  describe "skill_prompt_context/2 — full mode" do
    test "renders one line per skill with extras below threshold", %{agent: agent} do
      insert_skill!(agent, "a", "first skill description", "# skill a\n\nbody")
      insert_skill!(agent, "b", "second skill description", "# skill b\n\nbody")

      context = Skills.skill_prompt_context(agent.id)
      lines = String.split(context, "\n")

      assert Enum.count(lines) == 2
      assert Enum.any?(lines, &String.contains?(&1, "Test Skill a"))
      assert Enum.any?(lines, &String.contains?(&1, "first skill description"))
    end
  end

  describe "skill_prompt_context/2 — compact mode" do
    test "switches to compact format automatically when count >= threshold", %{agent: agent} do
      for i <- 1..10 do
        insert_skill!(agent, "n#{i}", "description #{i}", "body #{i}")
      end

      context = Skills.skill_prompt_context(agent.id)

      assert context =~ "10 skills available"
      assert context =~ "`skill_load`"
      # Each compact line begins with "- `slug`:"
      assert context =~ "- `test-skill-n1`:"
    end

    test "custom threshold override", %{agent: agent} do
      insert_skill!(agent, "x", "one", "body")
      insert_skill!(agent, "y", "two", "body")

      compact = Skills.skill_prompt_context(agent.id, %{compact_threshold: 1})
      assert compact =~ "2 skills available"
    end

    test "explicit style override beats threshold", %{agent: agent} do
      insert_skill!(agent, "x", "one", "body")
      insert_skill!(agent, "y", "two", "body")

      forced_compact = Skills.skill_prompt_context(agent.id, %{style: :compact})
      assert forced_compact =~ "2 skills available"
      assert forced_compact =~ "- `test-skill-x`:"

      forced_full = Skills.skill_prompt_context(agent.id, %{style: :full, compact_threshold: 1})
      refute forced_full =~ "2 skills available"
      assert forced_full =~ "Test Skill x"
    end

    test "compact descriptions are truncated at 100 chars", %{agent: agent} do
      long = String.duplicate("a", 200)
      insert_skill!(agent, "long", long, "body")

      compact = Skills.skill_prompt_context(agent.id, %{style: :compact})
      lines = String.split(compact, "\n")
      body_line = Enum.find(lines, &String.starts_with?(&1, "- "))
      desc = String.slice(body_line, String.length("- `test-skill-long`: "), 200)
      assert String.length(desc) <= 100
    end
  end

  describe "load_skill_body/2" do
    test "reads the markdown body by slug", %{agent: agent} do
      insert_skill!(agent, "body", "with body", "# body skill\n\nhello world")

      assert {:ok, %{slug: "test-skill-body", content: content, name: name}} =
               Skills.load_skill_body(agent.id, "test-skill-body")

      assert content =~ "hello world"
      assert name =~ "Test Skill body"
    end

    test "returns :not_found for unknown slugs", %{agent: agent} do
      assert {:error, :not_found} = Skills.load_skill_body(agent.id, "does-not-exist")
    end

    test "returns the file error when the file is missing", %{agent: agent, tmp_ws: tmp_ws} do
      skill = insert_skill!(agent, "gone", "missing file", "content")
      File.rm!(skill.path)

      assert {:error, :enoent} = Skills.load_skill_body(agent.id, "test-skill-gone")
      File.mkdir_p!(Path.join(tmp_ws, "skills"))
    end
  end

  describe "skill_load tool" do
    test "returns the loaded body with truncation metadata", %{agent: agent} do
      insert_skill!(agent, "t", "tool test", "line 1\nline 2\nline 3")

      assert {:ok, result} =
               SkillLoad.execute(%{"slug" => "test-skill-t", "agent_id" => agent.id}, %{})

      assert result.slug == "test-skill-t"
      assert result.content =~ "line 1"
      assert result.truncated == false
      assert result.size > 0
    end

    test "rejects missing slug" do
      assert {:error, :missing_slug} = SkillLoad.execute(%{"agent_id" => 1}, %{})
    end

    test "rejects missing agent_id" do
      assert {:error, :missing_agent_id} = SkillLoad.execute(%{"slug" => "anything"}, %{})
    end

    test "passes through :not_found from the runtime", %{agent: agent} do
      assert {:error, :not_found} =
               SkillLoad.execute(%{"slug" => "no-such-slug", "agent_id" => agent.id}, %{})
    end
  end
end
