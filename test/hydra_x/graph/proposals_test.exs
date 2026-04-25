defmodule HydraX.Graph.ProposalsTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Graph.Proposals
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.PretrainedProjects.ProductDevelopment
  alias HydraX.Product

  setup do
    email = "proposals-test+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{
        "email" => email,
        "display_name" => "Proposals Tester"
      })

    {:ok, project, _onboarding} =
      Product.create_project(%{
        "name" => "Proposals Test Project",
        "description" => "t",
        "workspace_id" => workspace.id
      })

    :ok = ProductDevelopment.apply_to_project(project.id)

    %{project: project}
  end

  describe "propose/4" do
    test "creates a pending proposal with the given change_kind + payload",
         %{project: project} do
      {:ok, proposal} =
        Proposals.propose(
          project.id,
          "add_node_type",
          %{
            "type_key" => "hypothesis",
            "display_name" => "Hypothesis",
            "extends" => "claim",
            "status_vocabulary" => ~w(proposed active superseded)
          },
          %{"rationale" => "New type for early-stage claims."}
        )

      assert proposal.status == "pending"
      assert proposal.change_kind == "add_node_type"
      assert proposal.payload["type_key"] == "hypothesis"
      assert proposal.rationale =~ "claims"
      assert proposal.project_id == project.id
    end
  end

  describe "approve/2 — add_node_type" do
    test "applies the change and primes the registry", %{project: project} do
      {:ok, proposal} =
        Proposals.propose(project.id, "add_node_type", %{
          "type_key" => "risk",
          "display_name" => "Risk",
          "extends" => "claim",
          "status_vocabulary" => ~w(open mitigated accepted)
        })

      {:ok, approved} = Proposals.approve(proposal, by_operator: true)
      assert approved.status == "approved"
      assert approved.applied_at
      assert approved.reviewed_by_operator

      assert {:ok, type_def} = SchemaRegistry.fetch_node_type(project.id, "risk")
      assert type_def.extends == "claim"
    end
  end

  describe "approve/2 — extend_node_type" do
    test "merges new properties into existing type's attribute_schema",
         %{project: project} do
      {:ok, proposal} =
        Proposals.propose(project.id, "extend_node_type", %{
          "type_key" => "insight",
          "properties" => %{
            "risk_score" => %{"type" => "number"}
          }
        })

      {:ok, _approved} = Proposals.approve(proposal, by_operator: true)

      {:ok, type_def} = SchemaRegistry.fetch_node_type(project.id, "insight")
      assert get_in(type_def.attribute_schema, ["properties", "risk_score"])
    end
  end

  describe "approve/2 — add_relationship_type" do
    test "adds a new relationship type", %{project: project} do
      {:ok, proposal} =
        Proposals.propose(project.id, "add_relationship_type", %{
          "type_key" => "refines",
          "display_name" => "Refines",
          "extends" => "supersedes"
        })

      {:ok, _} = Proposals.approve(proposal)

      assert {:ok, _def} = SchemaRegistry.fetch_relationship_type(project.id, "refines")
    end
  end

  describe "reject/2" do
    test "flips status to rejected without applying the change",
         %{project: project} do
      {:ok, proposal} =
        Proposals.propose(project.id, "add_node_type", %{
          "type_key" => "wont_be_added",
          "display_name" => "Nope",
          "extends" => "claim"
        })

      {:ok, rejected} = Proposals.reject(proposal, by_operator: true)
      assert rejected.status == "rejected"
      assert rejected.reviewed_by_operator

      assert :error == SchemaRegistry.fetch_node_type(project.id, "wont_be_added")
    end
  end

  describe "unsupported change kinds" do
    test "rolls back and leaves proposal pending", %{project: project} do
      {:ok, proposal} =
        %HydraX.Graph.SchemaChangeProposal{}
        |> HydraX.Graph.SchemaChangeProposal.changeset(%{
          project_id: project.id,
          change_kind: "add_node_type",
          payload: %{},
          status: "pending"
        })
        |> Repo.insert()

      proposal = %{proposal | change_kind: "remove_node_type"}

      assert {:error, {:unsupported_kind, "remove_node_type"}} =
               Proposals.approve(proposal)
    end
  end
end
