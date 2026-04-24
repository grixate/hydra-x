defmodule HydraX.Graph.ProposalsTest do
  use HydraX.DataCase, async: false

  alias HydraX.Graph.Domains
  alias HydraX.Graph.Domains.ProductDevelopment
  alias HydraX.Graph.Proposals
  alias HydraX.Graph.SchemaRegistry

  setup do
    {:ok, domain} = ProductDevelopment.seed()
    %{domain: domain}
  end

  describe "propose/4" do
    test "creates a pending proposal with the given change_kind + payload",
         %{domain: domain} do
      {:ok, proposal} =
        Proposals.propose(
          domain,
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
    end
  end

  describe "approve/2 — add_node_type" do
    test "applies the change and bumps domain version", %{domain: domain} do
      initial_version = domain.version

      {:ok, proposal} =
        Proposals.propose(domain, "add_node_type", %{
          "type_key" => "risk",
          "display_name" => "Risk",
          "extends" => "claim",
          "status_vocabulary" => ~w(open mitigated accepted)
        })

      {:ok, approved} = Proposals.approve(proposal, by_operator: true)
      assert approved.status == "approved"
      assert approved.applied_at
      assert approved.reviewed_by_operator

      # Allow a beat for PubSub to deliver and SchemaRegistry to populate.
      Process.sleep(50)

      assert {:ok, type_def} = SchemaRegistry.fetch_node_type(domain.id, "risk")
      assert type_def.extends == "claim"

      reloaded_domain = Domains.get_domain_by_slug("product_development")
      assert reloaded_domain.version != initial_version
    end
  end

  describe "approve/2 — extend_node_type" do
    test "merges new properties into existing type's attribute_schema",
         %{domain: domain} do
      {:ok, proposal} =
        Proposals.propose(domain, "extend_node_type", %{
          "type_key" => "insight",
          "properties" => %{
            "risk_score" => %{"type" => "number"}
          }
        })

      {:ok, _approved} = Proposals.approve(proposal, by_operator: true)
      Process.sleep(50)

      {:ok, type_def} = SchemaRegistry.fetch_node_type(domain.id, "insight")
      assert get_in(type_def.attribute_schema, ["properties", "risk_score"])
    end
  end

  describe "approve/2 — add_relationship_type" do
    test "adds a new relationship type", %{domain: domain} do
      {:ok, proposal} =
        Proposals.propose(domain, "add_relationship_type", %{
          "type_key" => "refines",
          "display_name" => "Refines",
          "extends" => "supersedes"
        })

      {:ok, _} = Proposals.approve(proposal)
      Process.sleep(50)

      assert {:ok, _def} = SchemaRegistry.fetch_relationship_type(domain.id, "refines")
    end
  end

  describe "reject/2" do
    test "flips status to rejected without applying the change",
         %{domain: domain} do
      {:ok, proposal} =
        Proposals.propose(domain, "add_node_type", %{
          "type_key" => "wont_be_added",
          "display_name" => "Nope",
          "extends" => "claim"
        })

      {:ok, rejected} = Proposals.reject(proposal, by_operator: true)
      assert rejected.status == "rejected"
      assert rejected.reviewed_by_operator

      # Not written to the registry.
      assert :error == SchemaRegistry.fetch_node_type(domain.id, "wont_be_added")
    end
  end

  describe "unsupported change kinds" do
    test "rolls back and leaves proposal pending", %{domain: domain} do
      {:ok, proposal} =
        %HydraX.Graph.SchemaChangeProposal{}
        |> HydraX.Graph.SchemaChangeProposal.changeset(%{
          domain_id: domain.id,
          change_kind: "add_node_type",
          payload: %{},
          status: "pending"
        })
        |> Repo.insert()

      # Force an unsupported kind to exercise the guard. (Direct struct
      # update bypasses the changeset's validate_inclusion, simulating a
      # proposal created before the kind was deprecated.)
      proposal = %{proposal | change_kind: "remove_node_type"}

      assert {:error, {:unsupported_kind, "remove_node_type"}} =
               Proposals.approve(proposal)
    end
  end
end
