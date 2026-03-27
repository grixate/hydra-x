defmodule HydraX.Product.AgentBridgeTest do
  use HydraX.DataCase

  alias HydraX.Product
  alias HydraX.Product.AgentBridge
  alias HydraX.Product.ProductMessage
  alias HydraX.Repo

  test "ensure_project_conversation reuses the hydra conversation for a persona/external ref pair" do
    {:ok, project} = Product.create_project(%{"name" => "Bridge Project"})

    assert {:ok, first} =
             AgentBridge.ensure_project_conversation(project, :researcher, %{
               "external_ref" => "bridge-session-1",
               "title" => "Research Session"
             })

    assert {:ok, second} =
             AgentBridge.ensure_project_conversation(project.id, "researcher", %{
               "external_ref" => "bridge-session-1",
               "title" => "Ignored on reuse"
             })

    assert first.id == second.id
    assert first.hydra_conversation_id == second.hydra_conversation_id
    assert first.persona == "researcher"
  end

  test "submit_message routes through the hydra channel and syncs linked product messages" do
    {:ok, project} = Product.create_project(%{"name" => "Bridge Submit"})

    {:ok, product_conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "bridge-submit-1"
      })

    assert {:ok, result} =
             AgentBridge.submit_message(product_conversation, "Remember the bridge.", %{
               "source" => "product_test"
             })

    assert result.product_conversation.id == product_conversation.id

    assert Repo.aggregate(ProductMessage, :count, :id) >= 1

    assert Repo.all(ProductMessage)
           |> Enum.any?(
             &(&1.product_conversation_id == product_conversation.id and
                 &1.content == "Remember the bridge.")
           )
  end
end
