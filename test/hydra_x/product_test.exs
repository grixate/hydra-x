defmodule HydraX.ProductTest do
  use HydraX.DataCase

  alias HydraX.Product

  test "create_project provisions researcher and strategist agents with project templates" do
    assert {:ok, project} =
             Product.create_project(%{
               "name" => "Operator Research Core",
               "description" => "Grounded product discovery."
             })

    assert project.slug == "operator-research-core"
    assert project.researcher_agent.role == "researcher"
    assert project.strategist_agent.role == "planner"
    assert project.architect_agent.role == "builder"
    assert project.designer_agent.role == "designer"
    assert project.memory_agent.role == "operator"

    assert File.read!(Path.join(project.researcher_agent.workspace_root, "IDENTITY.md")) =~
             "researcher for Operator Research Core"

    assert File.read!(Path.join(project.strategist_agent.workspace_root, "IDENTITY.md")) =~
             "strategist for Operator Research Core"
  end
end
