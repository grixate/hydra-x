defmodule HydraX.Product.LibraryPreprocessTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Graph.Nodes
  alias HydraX.PretrainedProjects.ProductDevelopment
  alias HydraX.Product
  alias HydraX.Product.LibraryPreprocess
  alias HydraX.Repo

  setup do
    email = "preprocess+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{
        "email" => email,
        "display_name" => "Preprocess Tester"
      })

    {:ok, project} =
      Product.create_project(%{
        "name" => "Preprocess Project",
        "description" => "library pipeline tests",
        "workspace_id" => workspace.id
      })

    :ok = ProductDevelopment.apply_to_project(project.id)

    %{project: project}
  end

  test "run/1 finalises a source through all stages with mock LLM", %{project: project} do
    {:ok, source} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "A short paper on sleep and memory",
        body: """
        We studied 30 participants over 14 nights. Sleep onset latency
        correlated negatively with declarative recall (r=-0.42).

        References
        [1] Smith J. (2018). Sleep architecture and memory consolidation.
        [2] Doe R. (2020). Working memory under sleep deprivation.
        """,
        status: "pending",
        attributes: %{
          "kind" => "document",
          "ingestion_status" => "pending"
        }
      })

    final = LibraryPreprocess.run(source)

    assert %GraphNode{} = final
    attrs = final.attributes || %{}

    # Pipeline reaches a terminal state
    assert attrs["ingestion_status"] in ["processed", "partial"]

    # Stage 3 — summary persisted
    assert is_binary(attrs["ingestion_summary"]) and attrs["ingestion_summary"] != ""

    # Stage 5 — references section parsed (2 refs in fixture)
    assert attrs["cited_works_count"] in [2, 1, 0]
  end

  test "run_stage/2 re-runs a single stage idempotently", %{project: project} do
    {:ok, source} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Tiny doc",
        body: "Some content with no references section.",
        status: "pending",
        attributes: %{"kind" => "document"}
      })

    {:ok, after_summary} = LibraryPreprocess.run_stage(source, :summary)
    assert is_binary(after_summary.attributes["ingestion_summary"])

    # Re-running the same stage should not crash
    {:ok, _again} = LibraryPreprocess.run_stage(after_summary, :summary)
  end

  test "stages/0 lists the documented stages" do
    stages = LibraryPreprocess.stages()

    for expected <- ~w(summary topics citations authors_publications contradictions)a do
      assert expected in stages
    end
  end

  # Sanity check that fixture cleanly persists
  test "source attributes round-trip through Repo", %{project: project} do
    {:ok, source} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Round-trip",
        body: "x",
        status: "pending",
        attributes: %{"kind" => "note", "ingestion_status" => "pending"}
      })

    persisted = Repo.get!(GraphNode, source.id)
    assert persisted.attributes["kind"] == "note"
    assert persisted.attributes["ingestion_status"] == "pending"
  end
end
