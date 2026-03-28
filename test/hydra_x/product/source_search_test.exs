defmodule HydraX.Product.SourceSearchTest do
  use HydraX.DataCase

  alias HydraX.Agent.PromptBuilder
  alias HydraX.Memory
  alias HydraX.Product
  alias HydraX.Product.AgentBridge
  alias HydraX.Runtime

  test "create_source indexes chunks and search_source_chunks returns grounded matches" do
    {:ok, project} = Product.create_project(%{"name" => "Grounded Retention"})

    assert {:ok, source} =
             Product.create_source(project, %{
               "title" => "Interview Notes",
               "source_type" => "markdown",
               "content" => """
               ## Retention
               Teams return every week because the dashboard highlights unresolved incidents and stalled launches.

               ## Alerts
               Operators want scheduled summaries and escalation alerts before launch windows.
               """
             })

    assert source.processing_status == "completed"
    assert length(source.source_chunks) >= 2

    [top | _rest] = Product.search_source_chunks(project, "weekly retention dashboard", limit: 3)

    assert top.chunk.source_id == source.id
    assert String.downcase(top.chunk.content) =~ "dashboard"
    assert "lexical match" in top.reasons
  end

  test "product conversations inject grounding context and expose the source_search tool" do
    {:ok, project} = Product.create_project(%{"name" => "Prompt Grounding"})

    {:ok, product_conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "prompt-grounding"
      })

    prompt =
      PromptBuilder.build(project.researcher_agent, [], nil, nil, %{
        tool_policy: %{},
        product_context: Product.prompt_context(product_conversation.hydra_conversation),
        extra_tool_modules: Product.tool_modules(product_conversation.hydra_conversation)
      })

    system = List.first(prompt.messages)
    tool_names = Enum.map(prompt.tools, & &1.name)

    assert system.content =~ "## Product Context"
    assert system.content =~ "Grounding rules"
    assert "source_search" in tool_names
    assert "insight_create" in tool_names
    assert "insight_update" in tool_names
    # researcher does not have requirement_create per agent spec
    refute "requirement_create" in tool_names
  end

  test "parse_citations rewrites cite markers and returns structured citation payloads" do
    {:ok, project} = Product.create_project(%{"name" => "Citation Project"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Beta Notes",
        "content" => "Users return for weekly summaries and launch readiness reviews."
      })

    chunk = Enum.min_by(source.source_chunks, & &1.ordinal)

    {content, citations} =
      Product.parse_citations(
        project,
        "Users asked for summaries [[cite:#{chunk.id}]] and repeated the same point [[cite:#{chunk.id}]]."
      )

    assert content == "Users asked for summaries [1] and repeated the same point [1]."

    assert citations == [
             %{
               index: 1,
               chunk_id: chunk.id,
               source_id: source.id,
               source_title: "Beta Notes",
               section: "Paragraph 1",
               excerpt: chunk.content
             }
           ]
  end

  test "create_source can mirror chunks into project agent memory for recall and bulletin support" do
    {:ok, project} = Product.create_project(%{"name" => "Memory Mirroring"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Launch Interviews",
        "content" =>
          "Operators want weekly release summaries and unresolved incident callouts before launch windows.",
        "mirror_to_memory" => true
      })

    mirror = source.metadata["memory_mirror"]

    assert mirror["status"] == "completed"

    assert mirror["mirrored_agent_ids"] == [
             project.researcher_agent_id,
             project.strategist_agent_id
           ]

    assert mirror["mirrored_memory_count"] == 2

    researcher_results = Memory.search_ranked(project.researcher_agent_id, "release summaries", 3)
    strategist_results = Memory.search_ranked(project.strategist_agent_id, "incident callouts", 3)

    assert Enum.any?(researcher_results, &(&1.entry.metadata["product_source_id"] == source.id))
    assert Enum.any?(strategist_results, &(&1.entry.metadata["product_source_id"] == source.id))

    assert Runtime.agent_bulletin(project.researcher_agent_id).memory_count >= 1
    assert Runtime.agent_bulletin(project.strategist_agent_id).memory_count >= 1
  end
end
