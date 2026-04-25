defmodule HydraX.Graph.PrimitivesTest do
  use ExUnit.Case, async: true

  alias HydraX.Graph.Primitives

  test "node_primitives includes the expected six" do
    assert Primitives.node_primitives() == ~w(claim evidence artifact activity entity agent_role)
  end

  test "relationship_primitives includes the expected eight" do
    assert Primitives.relationship_primitives() ==
             ~w(supports contradicts supersedes derives_from references depends_on produces measures)
  end

  test "node_primitive?/1 discriminates" do
    assert Primitives.node_primitive?("claim")
    refute Primitives.node_primitive?("supports")
    refute Primitives.node_primitive?("nonsense")
  end

  test "relationship_primitive?/1 discriminates" do
    assert Primitives.relationship_primitive?("supports")
    refute Primitives.relationship_primitive?("claim")
  end

  test "default_status_vocabulary for claim" do
    assert Primitives.default_status_vocabulary("claim") ==
             ~w(proposed active superseded retracted)
  end

  test "default_status_vocabulary falls back to empty for unknown primitive" do
    assert Primitives.default_status_vocabulary("nonsense") == []
  end
end
