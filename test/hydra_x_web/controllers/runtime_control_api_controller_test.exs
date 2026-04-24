defmodule HydraXWeb.RuntimeControlAPIControllerTest do
  use HydraXWeb.ConnCase

  alias HydraX.Product.Project
  alias HydraX.Product.ProductConversation
  alias HydraX.Repo

  alias HydraX.Runtime.{
    AgentProfile,
    Conversation,
    ConversationBranch,
    Conversations,
    ProviderConfig,
    SessionBranches
  }

  setup %{conn: conn} do
    suffix = System.unique_integer([:positive])

    # Two enabled provider configs so `switch_model` has something to pick.
    {:ok, p1} =
      %ProviderConfig{}
      |> ProviderConfig.changeset(%{
        "name" => "rt-sonnet-#{suffix}",
        "kind" => "anthropic",
        "base_url" => "https://api.anthropic.com",
        "api_key" => "sk-test",
        "model" => "rt-sonnet-#{suffix}",
        "enabled" => true
      })
      |> Repo.insert()

    {:ok, _p2} =
      %ProviderConfig{}
      |> ProviderConfig.changeset(%{
        "name" => "rt-haiku-#{suffix}",
        "kind" => "anthropic",
        "base_url" => "https://api.anthropic.com",
        "api_key" => "sk-test",
        "model" => "rt-haiku-#{suffix}",
        "enabled" => true
      })
      |> Repo.insert()

    researcher = insert_agent!("rt-researcher-#{suffix}")
    strategist = insert_agent!("rt-strategist-#{suffix}")

    project =
      %Project{}
      |> Project.changeset(%{
        "name" => "Runtime Control #{suffix}",
        "slug" => "runtime-control-#{suffix}",
        "researcher_agent_id" => researcher.id,
        "strategist_agent_id" => strategist.id
      })
      |> Repo.insert!()

    {:ok, hydra_conv} =
      %Conversation{}
      |> Conversation.changeset(%{
        "agent_id" => researcher.id,
        "channel" => "product_chat",
        "status" => "active",
        "metadata" => %{}
      })
      |> Repo.insert()

    {:ok, product_conv} =
      %ProductConversation{}
      |> ProductConversation.changeset(%{
        "project_id" => project.id,
        "persona" => "researcher",
        "hydra_conversation_id" => hydra_conv.id,
        "status" => "active"
      })
      |> Repo.insert()

    conn = put_req_header(conn, "accept", "application/json")

    {:ok,
     conn: conn,
     project: project,
     product_conv: product_conv,
     hydra_conv: hydra_conv,
     p1: p1,
     suffix: suffix}
  end

  defp insert_agent!(slug) do
    %AgentProfile{}
    |> AgentProfile.changeset(%{
      "name" => slug,
      "slug" => slug,
      "workspace_root" => Path.join(System.tmp_dir!(), "hx_rt_#{slug}")
    })
    |> Repo.insert!()
  end

  describe "GET /branches" do
    test "returns the main branch for a fresh conversation", %{
      conn: conn,
      project: project,
      product_conv: product_conv,
      hydra_conv: hydra_conv
    } do
      # Trigger main-branch creation by appending one turn.
      {:ok, _} =
        Conversations.append_turn(hydra_conv, %{
          "role" => "user",
          "kind" => "message",
          "content" => "hello"
        })

      conn =
        get(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/branches"
        )

      body = json_response(conn, 200)
      assert body["data"]["active_branch_uuid"] != nil
      assert [main] = body["data"]["branches"]
      assert main["label"] == "main"
      assert main["active"] == true
      assert main["turn_count"] == 1
    end
  end

  describe "POST /branches" do
    test "forks a new branch from a turn and activates it", %{
      conn: conn,
      project: project,
      product_conv: product_conv,
      hydra_conv: hydra_conv
    } do
      {:ok, t1} =
        Conversations.append_turn(hydra_conv, %{
          "role" => "user",
          "kind" => "message",
          "content" => "first"
        })

      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/branches",
          %{"from_turn_id" => t1.id, "label" => "alternate"}
        )

      body = json_response(conn, 201)
      assert body["data"]["label"] == "alternate"
      assert body["data"]["active"] == true
    end

    test "rejects missing label", %{
      conn: conn,
      project: project,
      product_conv: product_conv,
      hydra_conv: hydra_conv
    } do
      {:ok, t1} =
        Conversations.append_turn(hydra_conv, %{
          "role" => "user",
          "kind" => "message",
          "content" => "first"
        })

      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/branches",
          %{"from_turn_id" => t1.id, "label" => ""}
        )

      assert json_response(conn, 400)["error"] =~ "label required"
    end

    test "rejects unknown turn id", %{
      conn: conn,
      project: project,
      product_conv: product_conv
    } do
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/branches",
          %{"from_turn_id" => 999_999_999, "label" => "x"}
        )

      assert json_response(conn, 404)["error"] == "turn not found"
    end
  end

  describe "POST /branches/:branch_uuid/activate" do
    test "switches the active branch", %{
      conn: conn,
      project: project,
      product_conv: product_conv,
      hydra_conv: hydra_conv
    } do
      {:ok, t1} =
        Conversations.append_turn(hydra_conv, %{
          "role" => "user",
          "kind" => "message",
          "content" => "m1"
        })

      {:ok, branch} = SessionBranches.fork(t1, "side")
      conv_after = Repo.get!(Conversation, hydra_conv.id)

      main_row =
        Repo.get_by(ConversationBranch, conversation_id: hydra_conv.id, label: "main")

      main_uuid = main_row.branch_uuid

      # Switch back to main via the API.
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/branches/#{main_uuid}/activate",
          %{}
        )

      body = json_response(conn, 200)
      assert body["data"]["active_branch_uuid"] == main_uuid

      # Confirm the switch happened.
      refreshed = Repo.get!(Conversation, hydra_conv.id)
      assert refreshed.active_branch_id == main_uuid
      assert conv_after.active_branch_id == branch.branch_uuid
    end

    test "returns 404 for unknown branch_uuid", %{
      conn: conn,
      project: project,
      product_conv: product_conv
    } do
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/branches/#{Ecto.UUID.generate()}/activate",
          %{}
        )

      assert json_response(conn, 404)["error"] == "branch not found"
    end
  end

  describe "GET /models" do
    test "returns available models and current override (nil when unset)", %{
      conn: conn,
      project: project,
      product_conv: product_conv
    } do
      conn =
        get(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/models"
        )

      body = json_response(conn, 200)
      assert is_list(body["data"]["available"])
      assert body["data"]["current_override"] == nil
    end
  end

  describe "POST /model" do
    test "applies a model override", %{
      conn: conn,
      project: project,
      product_conv: product_conv,
      p1: p1
    } do
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/model",
          %{"model" => p1.model, "reason" => "need stronger reasoning"}
        )

      body = json_response(conn, 200)
      assert body["data"]["model"] == p1.model
      assert body["data"]["reason"] == "need stronger reasoning"
    end

    test "rejects unknown models with the catalog", %{
      conn: conn,
      project: project,
      product_conv: product_conv
    } do
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/model",
          %{"model" => "nope-not-here", "reason" => "nope"}
        )

      body = json_response(conn, 422)
      assert body["error"] == "model_not_available"
      assert is_list(body["available"])
    end
  end

  describe "POST /steer" do
    test "returns conflict when no channel is running", %{
      conn: conn,
      project: project,
      product_conv: product_conv
    } do
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/steer",
          %{"content" => "use postgres"}
        )

      assert json_response(conn, 409)["error"] =~ "no active channel"
    end

    test "rejects empty content", %{
      conn: conn,
      project: project,
      product_conv: product_conv
    } do
      conn =
        post(
          conn,
          ~p"/api/v1/projects/#{project.id}/conversations/#{product_conv.id}/steer",
          %{}
        )

      assert json_response(conn, 400)["error"] =~ "content required"
    end
  end
end
