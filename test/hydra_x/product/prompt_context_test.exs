defmodule HydraX.Product.PromptContextTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Product
  alias HydraX.SharedMemory

  defp project_with_scope! do
    email = "ctx+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{user: user, workspace: workspace}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "T"})

    {:ok, project} =
      Product.create_project(%{
        "name" => "ctx-#{System.unique_integer([:positive])}",
        "description" => "t",
        "workspace_id" => workspace.id
      })

    {:ok, scope} = SharedMemory.ensure_scope_for_user(user.id)
    {project, scope}
  end

  describe "prompt_context/1 shared_memory_section" do
    test "injects shared-memory nodes when the owner has them" do
      {project, scope} = project_with_scope!()

      {:ok, _} =
        SharedMemory.create_node(scope, %{
          "node_type" => "principle",
          "title" => "Ship weekly",
          "body" => "Momentum dies without weekly releases."
        })

      ctx =
        Product.prompt_context(%{
          "product_persona" => "strategist",
          "product_project_id" => to_string(project.id)
        })

      assert ctx =~ "Your identity & cross-project principles"
      assert ctx =~ "Ship weekly"
    end

    test "omits the shared-memory section when the owner has no nodes" do
      {project, _scope} = project_with_scope!()

      ctx =
        Product.prompt_context(%{
          "product_persona" => "strategist",
          "product_project_id" => to_string(project.id)
        })

      refute ctx =~ "Your identity & cross-project principles"
    end
  end
end
