defmodule HydraX.Graph.NodeTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Graph.Node
  alias HydraX.Graph.ProjectSchemas
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.PretrainedProjects.ProductDevelopment
  alias HydraX.Product

  setup do
    email = "node-test+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "Node Tester"})

    {:ok, project} =
      Product.create_project(%{
        "name" => "Node Test Project",
        "description" => "t",
        "workspace_id" => workspace.id
      })

    # Apply the built-in pretrained project to give this test project a
    # full product-development schema. Per the amendment, projects are
    # blank by default; tests opt in to the schema explicitly.
    :ok = ProductDevelopment.apply_to_project(project.id)

    %{project: project}
  end

  describe "changeset/2" do
    test "creates a valid insight node", %{project: project} do
      attrs = %{
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

    test "rejects an unknown type_key", %{project: project} do
      attrs = %{
        project_id: project.id,
        type_key: "nonsense",
        title: "X",
        status: "draft"
      }

      changeset = Node.changeset(%Node{}, attrs)
      refute changeset.valid?
      assert "is not defined for this project" in errors_on(changeset).type_key
    end

    test "rejects a status outside the type's vocabulary", %{project: project} do
      attrs = %{
        project_id: project.id,
        type_key: "insight",
        title: "X",
        status: "hyperactive"
      }

      changeset = Node.changeset(%Node{}, attrs)
      refute changeset.valid?
      assert "is not in the type's status vocabulary" in errors_on(changeset).status
    end

    test "rejects an attribute violating enum", %{project: project} do
      attrs = %{
        project_id: project.id,
        type_key: "decision",
        title: "Pick stack",
        status: "active",
        attributes: %{"reversibility" => "maybe"}
      }

      changeset = Node.changeset(%Node{}, attrs)
      refute changeset.valid?
      assert Enum.any?(errors_on(changeset).attributes, &(&1 =~ "reversibility"))
    end

    test "inserts and reads back with denormalized primitive", %{project: project} do
      attrs = %{
        project_id: project.id,
        type_key: "source",
        title: "The internet, volume 1",
        status: "completed",
        attributes: %{"external_ref" => "https://example.com"}
      }

      {:ok, node} = %Node{} |> Node.changeset(attrs) |> Repo.insert()
      reloaded = Repo.get!(Node, node.id)
      assert reloaded.extends_primitive == "evidence"
      assert reloaded.attributes["external_ref"] == "https://example.com"
    end
  end

  describe "ProjectSchemas.upsert_node_type/2" do
    test "primes SchemaRegistry after write", %{project: project} do
      # fresh type not present in the builtin pretrained project
      {:ok, _} =
        ProjectSchemas.upsert_node_type(project.id, %{
          type_key: "hypothesis",
          display_name: "Hypothesis",
          extends: "claim",
          status_vocabulary: ~w(proposed active superseded),
          attribute_schema: %{}
        })

      assert {:ok, type_def} = SchemaRegistry.fetch_node_type(project.id, "hypothesis")
      assert type_def.extends == "claim"
    end
  end
end
