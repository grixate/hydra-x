defmodule HydraX.Product.MentionsUpdateIntentTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Product
  alias HydraX.Product.Mention
  alias HydraX.Product.Mentions
  alias HydraX.Repo

  defp make_project! do
    email = "mentions+#{System.unique_integer([:positive])}@test.example.com"
    {:ok, %{workspace: workspace}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "T"})

    {:ok, project, _} =
      Product.create_project(%{
        "name" => "mentions-#{System.unique_integer([:positive])}",
        "description" => "t",
        "workspace_id" => workspace.id
      })

    project
  end

  defp insert_mention!(project, attrs) do
    %Mention{}
    |> Mention.changeset(
      Map.merge(
        %{
          "project_id" => project.id,
          "source_type" => "chat_message",
          "target_agent_id" => "strategist",
          "content" => "@strategist look into this",
          "intent" => "share_context",
          "metadata" => %{"ambiguous_intent" => true, "inferred" => "request_task"}
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "update_intent/2" do
    test "accepts a valid intent, clears ambiguous flag, and broadcasts mention.updated" do
      project = make_project!()
      mention = insert_mention!(project, %{})

      HydraX.Product.PubSub.subscribe_project(project)

      assert {:ok, updated} = Mentions.update_intent(mention, "share_context")
      assert updated.intent == "share_context"
      assert updated.metadata["ambiguous_intent"] == false

      assert_receive {:product_project_event, "mention.updated", %{mention: ^updated}}, 1_000
    end

    test "rejects an unknown intent" do
      project = make_project!()
      mention = insert_mention!(project, %{})

      assert {:error, :invalid_intent} = Mentions.update_intent(mention, "not_a_real_intent")
    end

    test "dispatches task spawn when intent flips to request_task and no task exists" do
      project = make_project!()
      mention = insert_mention!(project, %{"target_task_id" => nil})

      assert {:ok, updated} = Mentions.update_intent(mention, "request_task")
      assert updated.intent == "request_task"
      # Side-effect dispatch: a task is created for the target agent.
      refute is_nil(updated.target_task_id)
    end

    test "does not re-dispatch when task already exists" do
      project = make_project!()

      # Pre-seed a task then a mention pointing at it.
      {:ok, task} =
        HydraX.Product.AgentTasks.create_task(%{
          project_id: project.id,
          agent_id: "strategist",
          title: "preexisting",
          state: "pending",
          priority: "normal",
          assigned_by: "system"
        })

      mention =
        insert_mention!(project, %{
          "intent" => "request_task",
          "target_task_id" => task.id
        })

      assert {:ok, updated} = Mentions.update_intent(mention, "request_task")
      # Task id unchanged — no duplicate spawn.
      assert updated.target_task_id == task.id
    end
  end
end
