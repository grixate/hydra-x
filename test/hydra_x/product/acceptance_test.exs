defmodule HydraX.Product.AcceptanceTest do
  use HydraX.DataCase

  alias HydraX.Product
  alias HydraX.Product.AgentBridge
  alias HydraX.Runtime

  test "research workflow stays grounded from cited answer to accepted requirement" do
    {:ok, project} = Product.create_project(%{"name" => "Research Acceptance"})

    assert project.researcher_agent_id
    assert project.strategist_agent_id
    assert project.researcher_agent.slug =~ "researcher"
    assert project.strategist_agent.slug =~ "strategist"

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Operator Interviews",
        "content" => """
        Operators asked for weekly release summaries ahead of launch windows.
        They also want unresolved incidents called out before a launch review starts.
        """
      })

    chunk = Enum.min_by(source.source_chunks, & &1.ordinal)

    {:ok, provider} =
      Runtime.save_provider_config(%{
        name: "Grounded Acceptance Provider",
        kind: "openai_compatible",
        base_url: "https://grounded-acceptance.test",
        api_key: "secret",
        model: "gpt-grounded-acceptance",
        enabled: false
      })

    {:ok, _agent} =
      Runtime.save_agent_provider_routing(project.researcher_agent_id, %{
        "default_provider_id" => provider.id
      })

    previous_request_fn = Application.get_env(:hydra_x, :provider_request_fn)
    test_pid = self()

    Application.put_env(:hydra_x, :provider_request_fn, fn _opts ->
      send(test_pid, :provider_requested)

      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   "Operators asked for weekly release summaries before launch windows [[cite:#{chunk.id}]].",
                 "tool_calls" => nil
               },
               "finish_reason" => "stop"
             }
           ]
         }
       }}
    end)

    on_exit(fn ->
      if previous_request_fn do
        Application.put_env(:hydra_x, :provider_request_fn, previous_request_fn)
      else
        Application.delete_env(:hydra_x, :provider_request_fn)
      end
    end)

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "acceptance-researcher"
      })

    assert {:ok, result} =
             AgentBridge.submit_message(
               conversation,
               "What did operators ask for before launch windows?",
               %{"source" => "acceptance_test"}
             )

    assert_receive :provider_requested, 1_000
    assert result.product_conversation.id == conversation.id

    refreshed_conversation = AgentBridge.get_project_conversation!(project, conversation.id)

    assert %{sources: 1, insights: 0, requirements: 0, conversations: 1} ==
             Product.project_counts(project)

    assert [user_message, assistant_message] = refreshed_conversation.product_messages
    assert user_message.role == "user"
    assert user_message.content =~ "before launch windows"
    assert assistant_message.role == "assistant"
    assert assistant_message.content =~ "weekly release summaries before launch windows [1]."
    refute assistant_message.content =~ "[[cite:"

    assert [citation] = assistant_message.citations
    assert citation_value(citation, "index") == 1
    assert citation_value(citation, "chunk_id") == chunk.id
    assert citation_value(citation, "source_id") == source.id
    assert citation_value(citation, "source_title") == source.title

    assert {:ok, draft_insight} =
             Product.create_insight(project, %{
               "title" => "Weekly Release Summaries",
               "body" => "Operators asked for weekly release summaries before launch windows.",
               "evidence_chunk_ids" => [citation_value(citation, "chunk_id")]
             })

    assert draft_insight.status == "draft"

    assert {:ok, accepted_insight} =
             Product.update_insight(draft_insight, %{
               "title" => "Weekly Release Summaries",
               "body" =>
                 "Operators consistently asked for weekly release summaries before launch windows.",
               "status" => "accepted"
             })

    assert accepted_insight.status == "accepted"

    assert {:ok, requirement} =
             Product.create_requirement(project, %{
               "title" => "Weekly Release Summary Workflow",
               "body" =>
                 "The product must produce weekly release summaries ahead of launch windows.",
               "insight_ids" => [accepted_insight.id],
               "status" => "accepted"
             })

    assert requirement.grounded
    assert requirement.status == "accepted"

    traced_requirement = Product.get_project_requirement!(project, requirement.id)
    assert [requirement_insight] = traced_requirement.requirement_insights
    assert requirement_insight.insight.id == accepted_insight.id
    assert requirement_insight.insight.status == "accepted"

    assert [insight_evidence] = requirement_insight.insight.insight_evidence
    assert insight_evidence.source_chunk.id == chunk.id
    assert insight_evidence.source_chunk.source.id == source.id
    assert insight_evidence.source_chunk.source.title == source.title

    assert %{sources: 1, insights: 1, requirements: 1, conversations: 1} ==
             Product.project_counts(project)
  end

  defp citation_value(citation, key) when is_map(citation) and is_binary(key) do
    Map.get(citation, key) || Map.get(citation, citation_atom_key(key))
  end

  defp citation_atom_key("index"), do: :index
  defp citation_atom_key("chunk_id"), do: :chunk_id
  defp citation_atom_key("source_id"), do: :source_id
  defp citation_atom_key("source_title"), do: :source_title
end
