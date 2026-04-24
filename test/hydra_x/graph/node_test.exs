defmodule HydraX.Graph.NodeTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Graph.Domains
  alias HydraX.Graph.Domains.ProductDevelopment
  alias HydraX.Graph.Node
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.Product

  setup do
    {:ok, domain} = ProductDevelopment.seed()

    email = "node-test+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "Node Tester"})

    {:ok, project, _onboarding} =
      Product.create_project(%{
        "name" => "Node Test Project",
        "description" => "t",
        "workspace_id" => workspace.id
      })

    %{domain: domain, project: project}
  end

  describe "changeset/2" do
    test "creates a valid insight node", %{domain: domain, project: project} do
      attrs = %{
        domain_id: domain.id,
        project_id: project.id,
        type_key: "insight",
        title: "Users want faster onboarding",
        status: "draft",
        attributes: %{
          "summary" => "From three recent interviews.",
          "evidence_strength" => "moderate"
        }
      }

      changeset = Node.changeset(%Node{}, attrs)
      assert changeset.valid?, "expected valid changeset, got: #{inspect(changeset.errors)}"
      assert get_field(changeset, :extends_primitive) == "claim"
    end

    test "rejects an unknown type_key", %{domain: domain, project: project} do
      attrs = %{
        domain_id: domain.id,
        project_id: project.id,
        type_key: "nonsense",
        title: "X",
        status: "draft"
      }

      changeset = Node.changeset(%Node{}, attrs)
      refute changeset.valid?
      assert "is not defined for this domain" in errors_on(changeset).type_key
    end

    test "rejects a status outside the type's vocabulary", %{domain: domain, project: project} do
      attrs = %{
        domain_id: domain.id,
        project_id: project.id,
        type_key: "insight",
        title: "X",
        status: "hyperactive"
      }

      changeset = Node.changeset(%Node{}, attrs)
      refute changeset.valid?
      assert "is not in the type's status vocabulary" in errors_on(changeset).status
    end

    test "rejects an attribute violating enum", %{domain: domain, project: project} do
      attrs = %{
        domain_id: domain.id,
        project_id: project.id,
        type_key: "decision",
        title: "Pick stack",
        status: "proposed",
        attributes: %{"reversibility" => "maybe"}
      }

      changeset = Node.changeset(%Node{}, attrs)
      refute changeset.valid?
      assert Enum.any?(errors_on(changeset).attributes, &(&1 =~ "reversibility"))
    end

    test "inserts and reads back with denormalized primitive", %{domain: domain, project: project} do
      attrs = %{
        domain_id: domain.id,
        project_id: project.id,
        type_key: "source",
        title: "The internet, volume 1",
        status: "candidate",
        attributes: %{"url" => "https://example.com"}
      }

      {:ok, node} = %Node{} |> Node.changeset(attrs) |> Repo.insert()
      reloaded = Repo.get!(Node, node.id)
      assert reloaded.extends_primitive == "evidence"
      assert reloaded.attributes["url"] == "https://example.com"
    end
  end

  describe "Domains.upsert_node_type/2" do
    test "bumps SchemaRegistry after write", %{domain: domain} do
      # fresh type not present in the builtin seed
      {:ok, _} =
        Domains.upsert_node_type(domain, %{
          type_key: "hypothesis",
          display_name: "Hypothesis",
          extends: "claim",
          status_vocabulary: ~w(proposed active superseded),
          attribute_schema: %{}
        })

      # short sleep to let PubSub deliver invalidation
      Process.sleep(50)

      assert {:ok, type_def} = SchemaRegistry.fetch_node_type(domain.id, "hypothesis")
      assert type_def.extends == "claim"
    end
  end
end
