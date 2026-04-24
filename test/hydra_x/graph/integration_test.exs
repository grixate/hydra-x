defmodule HydraX.Graph.IntegrationTest do
  @moduledoc """
  Reference end-to-end test proving the substrate can express the
  current product-development workflows. Walks through:

    1. Seed the `product_development` domain.
    2. Create an insight node (extends `claim`) and a source node
       (extends `evidence`).
    3. Link them with a `supports` relationship.
    4. Raise and resolve an `orphaned` flag on an unconnected node.
    5. Traverse from primitive to confirm engine-level queries work
       without knowing type keys.

  When this test passes, the existing typed `Insights`, `Sources`, and
  `graph_flags` contexts can — in principle — be replaced with calls
  into `Graph.Nodes`, `Graph.Relationships`, and `Graph.Flags`.
  """

  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Graph.Domains.ProductDevelopment
  alias HydraX.Graph.Flags
  alias HydraX.Graph.Nodes
  alias HydraX.Graph.Relationships
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.Product

  setup do
    {:ok, domain} = ProductDevelopment.seed()

    email = "integration+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{
        "email" => email,
        "display_name" => "Integration Tester"
      })

    {:ok, project, _onboarding} =
      Product.create_project(%{
        "name" => "Integration Project",
        "description" => "substrate E2E",
        "workspace_id" => workspace.id
      })

    %{domain: domain, project: project}
  end

  test "insight + source + supports + flag lifecycle", %{domain: domain, project: project} do
    # 1. Create an insight (claim primitive)
    {:ok, insight} =
      Nodes.create_node(domain, project.id, %{
        type_key: "insight",
        title: "Onboarding friction peaks at step 3",
        body: "Multiple interviews corroborate step-3 drop-off.",
        status: "accepted",
        confidence: 0.72,
        attributes: %{
          "summary" => "Step-3 drop-off is the dominant failure mode.",
          "evidence_strength" => "moderate"
        }
      })

    assert insight.extends_primitive == "claim"
    assert insight.scope == "project"
    assert insight.scope_root_id == project.id

    # 2. Create a source (evidence primitive)
    {:ok, source} =
      Nodes.create_node(domain, project.id, %{
        type_key: "source",
        title: "Interview transcript: user-17",
        status: "completed",
        attributes: %{"external_ref" => "https://example.com/transcripts/17"}
      })

    assert source.extends_primitive == "evidence"

    # 3. Link source --supports--> insight
    {:ok, edge} = Relationships.create_relationship(domain, source, insight, "supports")
    assert edge.extends_primitive == "supports"

    # Verify traversal from primitive (domain-neutral)
    claim_supports =
      Relationships.list_by_primitive(project.id, "supports")

    assert length(claim_supports) == 1
    assert hd(claim_supports).from_node_id == source.id
    assert hd(claim_supports).to_node_id == insight.id

    # The insight should have one incoming relationship — not an orphan.
    refute Relationships.orphan?(insight)
    refute Relationships.orphan?(source)

    # 4. Create an unconnected node and raise an `orphaned` flag on it
    {:ok, dangling} =
      Nodes.create_node(domain, project.id, %{
        type_key: "insight",
        title: "Draft with no evidence yet",
        status: "draft",
        attributes: %{}
      })

    assert Relationships.orphan?(dangling)

    {:ok, flag} =
      Flags.raise_flag(dangling, "orphaned", %{
        detected_by_agent_id: "coherence",
        detection_context: %{"reason" => "no_relationships"}
      })

    assert flag.flag_type_key == "orphaned"
    assert flag.severity == "warning"
    assert is_nil(flag.resolved_at)

    # Open flags listing
    assert [open] = Flags.open_flags(dangling)
    assert open.id == flag.id

    # Resolve the flag
    {:ok, resolved} = Flags.resolve_flag(flag, by_operator: true)
    assert resolved.resolved_by_operator
    assert not is_nil(resolved.resolved_at)
    assert Flags.open_flags(dangling) == []

    # 5. Filter nodes by primitive — engine-style query
    claims = Nodes.list_by_primitive(project.id, "claim")
    evidence = Nodes.list_by_primitive(project.id, "evidence")

    assert length(claims) == 2
    assert length(evidence) == 1
    assert Enum.all?(claims, &(&1.extends_primitive == "claim"))
  end

  test "raising an unknown flag type is rejected", %{domain: domain, project: project} do
    {:ok, node} =
      Nodes.create_node(domain, project.id, %{
        type_key: "insight",
        title: "x",
        status: "draft"
      })

    assert {:error, :unknown_flag_type} = Flags.raise_flag(node, "definitely_not_a_flag")
  end

  test "cross-project relationships are rejected", %{domain: domain, project: project} do
    email2 = "integration2+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: ws2}} =
      Accounts.create_user_with_workspace(%{
        "email" => email2,
        "display_name" => "Other Workspace"
      })

    {:ok, other_project, _} =
      Product.create_project(%{
        "name" => "Other",
        "description" => "t",
        "workspace_id" => ws2.id
      })

    {:ok, a} =
      Nodes.create_node(domain, project.id, %{
        type_key: "insight",
        title: "A",
        status: "draft"
      })

    {:ok, b} =
      Nodes.create_node(domain, other_project.id, %{
        type_key: "insight",
        title: "B",
        status: "draft"
      })

    assert {:error, :cross_project_relationship} =
             Relationships.create_relationship(domain, a, b, "supports")
  end
end
