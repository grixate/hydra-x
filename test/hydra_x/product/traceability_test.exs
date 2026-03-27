defmodule HydraX.Product.TraceabilityTest do
  use HydraX.DataCase

  alias HydraX.Product

  test "create_insight requires evidence chunk ids and links evidence to source chunks" do
    {:ok, project} = Product.create_project(%{"name" => "Traceability Core"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Interview Notes",
        "content" =>
          "Operators rely on release readiness summaries and unresolved incident reviews."
      })

    chunk = hd(source.source_chunks)

    assert {:error, changeset} =
             Product.create_insight(project, %{
               "title" => "Missing Evidence",
               "body" => "This should fail without evidence."
             })

    assert "must include at least one source chunk" in errors_on(changeset).metadata

    assert {:ok, insight} =
             Product.create_insight(project, %{
               "title" => "Release Readiness Matters",
               "body" => "Operators rely on weekly release readiness summaries.",
               "evidence_chunk_ids" => [chunk.id]
             })

    assert length(insight.insight_evidence) == 1
    assert hd(insight.insight_evidence).source_chunk_id == chunk.id
    assert hd(insight.insight_evidence).source_chunk.source.title == "Interview Notes"
  end

  test "create_requirement derives grounding from linked insights and blocks accepting ungrounded records" do
    {:ok, project} = Product.create_project(%{"name" => "Requirement Grounding"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Research",
        "content" => "Teams need launch reviews before release windows."
      })

    chunk = hd(source.source_chunks)

    {:ok, grounded_insight} =
      Product.create_insight(project, %{
        "title" => "Launch Reviews",
        "body" => "Teams need launch reviews before release windows.",
        "evidence_chunk_ids" => [chunk.id],
        "status" => "accepted"
      })

    assert {:ok, requirement} =
             Product.create_requirement(project, %{
               "title" => "Add Launch Review Workflow",
               "body" => "The product must support pre-release launch review workflows.",
               "insight_ids" => [grounded_insight.id],
               "status" => "accepted"
             })

    assert requirement.grounded
    assert requirement.status == "accepted"
    assert length(requirement.requirement_insights) == 1

    assert {:error, changeset} =
             Product.create_requirement(project, %{
               "title" => "Ungrounded Requirement",
               "body" => "This should not be accepted without evidence.",
               "status" => "accepted"
             })

    assert "cannot accept an ungrounded requirement" in errors_on(changeset).status
  end
end
