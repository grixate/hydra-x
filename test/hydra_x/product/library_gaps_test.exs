defmodule HydraX.Product.LibraryGapsTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Graph.Nodes
  alias HydraX.Graph.Relationships
  alias HydraX.PretrainedProjects.ProductDevelopment
  alias HydraX.Product
  alias HydraX.Product.LibraryGaps

  setup do
    email = "gaps+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{
        "email" => email,
        "display_name" => "Gaps Tester"
      })

    {:ok, project} =
      Product.create_project(%{
        "name" => "Gaps Project",
        "description" => "library gap detection tests",
        "workspace_id" => workspace.id
      })

    :ok = ProductDevelopment.apply_to_project(project.id)

    %{project: project}
  end

  test "sparse_topics surfaces topics with < threshold sources", %{project: project} do
    {:ok, topic_dense} =
      Nodes.create_node(project.id, %{
        type_key: "topic",
        title: "Dense Topic",
        status: "active",
        attributes: %{"granularity" => "medium", "description" => "lots of sources"}
      })

    {:ok, topic_sparse} =
      Nodes.create_node(project.id, %{
        type_key: "topic",
        title: "Sparse Topic",
        status: "active",
        attributes: %{"granularity" => "fine", "description" => "only one source"}
      })

    # Two sources point at dense, one at sparse
    {:ok, src_a} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Source A",
        body: "x",
        status: "completed",
        attributes: %{"kind" => "document"}
      })

    {:ok, src_b} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Source B",
        body: "x",
        status: "completed",
        attributes: %{"kind" => "document"}
      })

    {:ok, src_c} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Source C",
        body: "x",
        status: "completed",
        attributes: %{"kind" => "document"}
      })

    {:ok, _} = Relationships.create_relationship(src_a, topic_dense, "is_about")
    {:ok, _} = Relationships.create_relationship(src_b, topic_dense, "is_about")
    {:ok, _} = Relationships.create_relationship(src_c, topic_sparse, "is_about")

    sparse = LibraryGaps.sparse_topics(project.id, threshold: 2)

    titles = Enum.map(sparse, fn r -> r.topic.title end)
    assert "Sparse Topic" in titles
    refute "Dense Topic" in titles
  end

  test "citation_gaps surfaces sources with cited_works_count beyond library cites", %{
    project: project
  } do
    {:ok, src} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Citing source",
        body: "x",
        status: "completed",
        attributes: %{"kind" => "document", "cited_works_count" => 14}
      })

    {:ok, _other} =
      Nodes.create_node(project.id, %{
        type_key: "source",
        title: "Not a match",
        body: "x",
        status: "completed",
        attributes: %{"kind" => "document"}
      })

    rows = LibraryGaps.citation_gaps(project.id)
    assert [%{source: %{id: id}, gap: 14}] = Enum.filter(rows, fn r -> r.source.id == src.id end)
    assert id == src.id
  end

  test "summarise/1 returns all four buckets", %{project: project} do
    bundle = LibraryGaps.summarise(project.id)
    assert is_list(bundle.sparse_topics)
    assert is_list(bundle.recency_gaps)
    assert is_list(bundle.author_monocultures)
    assert is_list(bundle.citation_gaps)
  end
end
