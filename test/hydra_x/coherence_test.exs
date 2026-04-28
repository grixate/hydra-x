defmodule HydraX.CoherenceTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Coherence
  alias HydraX.Product

  defp make_project! do
    email = "coherence+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "T"})

    {:ok, project} =
      Product.create_project(%{
        "name" => "coherence-#{System.unique_integer([:positive])}",
        "description" => "t",
        "workspace_id" => workspace.id
      })

    project
  end

  defp record!(project, attrs) do
    base = %{
      "project_id" => project.id,
      "mode" => "in_project",
      "node_a_type" => "insight",
      "node_a_id" => 1,
      "node_a_scope" => "project",
      "node_b_type" => "requirement",
      "node_b_id" => 2,
      "node_b_scope" => "project",
      "severity" => "medium",
      "confidence" => "high",
      "explanation" => "conflict"
    }

    {:ok, c} = Coherence.record_detection(Map.merge(base, attrs))
    c
  end

  describe "badge_counts_for_project/1" do
    test "returns severity mix per node" do
      project = make_project!()
      record!(project, %{"node_a_id" => 10, "node_b_id" => 20, "severity" => "high"})
      record!(project, %{"node_a_id" => 10, "node_b_id" => 21, "severity" => "medium"})

      counts = Coherence.badge_counts_for_project(project.id)

      # node A surfaces under both pairs (A=10). Its severities list should
      # contain both high and medium.
      severities = Map.get(counts, {"insight", 10}, []) |> Enum.sort()
      assert severities == ["high", "medium"]
    end

    test "excludes dismissed contradictions" do
      project = make_project!()
      c = record!(project, %{"node_a_id" => 50, "node_b_id" => 51, "severity" => "high"})

      {:ok, _} = Coherence.dismiss(c, reason: "tester")

      counts = Coherence.badge_counts_for_project(project.id)
      refute Map.has_key?(counts, {"insight", 50})
    end
  end

  describe "list_for_node/2" do
    test "returns [] for non-integer ids instead of crashing" do
      assert Coherence.list_for_node("insight", "not-an-int") == []
      assert Coherence.list_for_node("insight", Ecto.UUID.generate()) == []
    end

    test "returns matching contradictions for integer node ids" do
      project = make_project!()
      c = record!(project, %{"node_a_id" => 77, "node_b_id" => 78})

      results = Coherence.list_for_node("insight", 77)
      assert Enum.any?(results, &(&1.id == c.id))
    end
  end

  describe "record_detection/1 pair normalisation" do
    test "collapses (A,B) and (B,A) into a single row" do
      project = make_project!()

      record!(project, %{
        "node_a_type" => "insight",
        "node_a_id" => 1,
        "node_b_type" => "requirement",
        "node_b_id" => 2
      })

      record!(project, %{
        "node_a_type" => "requirement",
        "node_a_id" => 2,
        "node_b_type" => "insight",
        "node_b_id" => 1
      })

      all = Coherence.list_for_project(project.id)
      # Both calls hit the same canonical pair — exactly one row exists,
      # with last_confirmed_at bumped from the re-detection.
      assert length(all) == 1
    end
  end
end
