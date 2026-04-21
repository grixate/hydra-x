defmodule HydraX.Tools.SwitchModelTest do
  use HydraX.DataCase, async: false

  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Conversation, Providers, ProviderConfig}
  alias HydraX.Tools.SwitchModel

  setup do
    suffix = System.unique_integer([:positive])

    # Insert two enabled provider configs with different models.
    {:ok, p1} =
      %ProviderConfig{}
      |> ProviderConfig.changeset(%{
        "name" => "anthropic-sonnet-#{suffix}",
        "kind" => "anthropic",
        "base_url" => "https://api.anthropic.com",
        "api_key" => "sk-test",
        "model" => "claude-sonnet-4-#{suffix}",
        "enabled" => true
      })
      |> Repo.insert()

    {:ok, p2} =
      %ProviderConfig{}
      |> ProviderConfig.changeset(%{
        "name" => "anthropic-haiku-#{suffix}",
        "kind" => "anthropic",
        "base_url" => "https://api.anthropic.com",
        "api_key" => "sk-test",
        "model" => "claude-haiku-4-#{suffix}",
        "enabled" => true
      })
      |> Repo.insert()

    agent =
      %AgentProfile{}
      |> AgentProfile.changeset(%{
        "name" => "switcher-#{suffix}",
        "slug" => "switcher-#{suffix}",
        "workspace_root" => Path.join(System.tmp_dir!(), "hx_sw_#{suffix}")
      })
      |> Repo.insert!()

    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{
        "agent_id" => agent.id,
        "channel" => "test",
        "status" => "active",
        "metadata" => %{}
      })
      |> Repo.insert()

    {:ok, suffix: suffix, p1: p1, p2: p2, agent: agent, conversation: conversation}
  end

  describe "find_provider_by_model/1" do
    test "returns the matching enabled provider", %{p1: p1} do
      assert %ProviderConfig{id: id} = Providers.find_provider_by_model(p1.model)
      assert id == p1.id
    end

    test "returns nil for unknown models" do
      assert is_nil(Providers.find_provider_by_model("nope-not-a-model"))
    end

    test "ignores disabled providers" do
      {:ok, disabled} =
        %ProviderConfig{}
        |> ProviderConfig.changeset(%{
          "name" => "disabled-#{System.unique_integer([:positive])}",
          "kind" => "anthropic",
          "base_url" => "https://api.anthropic.com",
          "api_key" => "sk-test",
          "model" => "should-be-hidden",
          "enabled" => false
        })
        |> Repo.insert()

      assert is_nil(Providers.find_provider_by_model(disabled.model))
    end
  end

  describe "list_available_models/0" do
    test "returns every enabled provider's model", %{p1: p1, p2: p2} do
      models = Providers.list_available_models()
      assert p1.model in models
      assert p2.model in models
    end
  end

  describe "SwitchModel.execute/2" do
    test "writes the override to conversation metadata", %{p1: p1, conversation: conv} do
      assert {:ok, %{model: model, provider_id: provider_id}} =
               SwitchModel.execute(
                 %{
                   "conversation_id" => conv.id,
                   "model" => p1.model,
                   "reason" => "needed stronger reasoning"
                 },
                 %{}
               )

      assert model == p1.model
      assert provider_id == p1.id

      reloaded = Repo.get!(Conversation, conv.id)
      assert reloaded.metadata["model_override_provider_id"] == p1.id
      assert reloaded.metadata["model_override_model"] == p1.model
      assert reloaded.metadata["model_override_reason"] == "needed stronger reasoning"
    end

    test "rejects unknown models with the catalog in the error", %{conversation: conv} do
      assert {:error, {:model_not_available, "nope", models}} =
               SwitchModel.execute(
                 %{
                   "conversation_id" => conv.id,
                   "model" => "nope",
                   "reason" => "trying to break it"
                 },
                 %{}
               )

      assert is_list(models)
    end

    test "rejects missing model / reason / conversation_id", %{conversation: conv} do
      assert {:error, :missing_conversation_id} =
               SwitchModel.execute(%{"model" => "x", "reason" => "y"}, %{})

      assert {:error, :missing_model} =
               SwitchModel.execute(%{"conversation_id" => conv.id, "reason" => "y"}, %{})

      assert {:error, :missing_reason} =
               SwitchModel.execute(%{"conversation_id" => conv.id, "model" => "x"}, %{})
    end

    test "returns conversation_not_found for a bogus id", %{p1: p1} do
      assert {:error, :conversation_not_found} =
               SwitchModel.execute(
                 %{"conversation_id" => 999_999_999, "model" => p1.model, "reason" => "oops"},
                 %{}
               )
    end
  end

  describe "allowed_models validation" do
    test "rejects models not in the agent's allowlist", %{agent: agent, conversation: conv, p1: p1, p2: _p2} do
      # Restrict the agent to only the sonnet model.
      {:ok, updated} =
        agent
        |> AgentProfile.changeset(%{"runtime_state" => %{"allowed_models" => [p1.model]}})
        |> Repo.update()

      assert updated.runtime_state["allowed_models"] == [p1.model]

      # Switching to p1 (allowed) works.
      assert {:ok, _} =
               SwitchModel.execute(
                 %{"conversation_id" => conv.id, "model" => p1.model, "reason" => "ok"},
                 %{}
               )

      # Switching to a non-allowed model is rejected.
      assert {:error, {:model_not_allowed, "other-model", _}} =
               SwitchModel.execute(
                 %{"conversation_id" => conv.id, "model" => "other-model", "reason" => "no"},
                 %{}
               )
    end

    test "nil allowed_models means any enabled model works", %{agent: _agent, conversation: conv, p1: p1, p2: p2} do
      # No allowlist set → both models work.
      assert {:ok, _} =
               SwitchModel.execute(
                 %{"conversation_id" => conv.id, "model" => p1.model, "reason" => "first"},
                 %{}
               )

      assert {:ok, _} =
               SwitchModel.execute(
                 %{"conversation_id" => conv.id, "model" => p2.model, "reason" => "second"},
                 %{}
               )
    end
  end

  describe "effective_provider_route/3 honours conversation override" do
    test "per-conversation override beats agent defaults", %{
      agent: agent,
      conversation: conv,
      p1: p1,
      p2: p2
    } do
      # First, set agent default to p2 (haiku).
      {:ok, _} =
        Providers.save_agent_provider_routing(agent.id, %{
          "default_provider_id" => p2.id
        })

      # Baseline: no override, uses agent default (haiku).
      route_default =
        Providers.effective_provider_route(agent.id, "channel", conversation_id: conv.id)

      assert route_default.provider.id == p2.id

      # Apply a per-conversation override to p1 (sonnet).
      {:ok, _} =
        SwitchModel.execute(
          %{"conversation_id" => conv.id, "model" => p1.model, "reason" => "complex"},
          %{}
        )

      route_overridden =
        Providers.effective_provider_route(agent.id, "channel", conversation_id: conv.id)

      assert route_overridden.provider.id == p1.id
      assert route_overridden.provider.model == p1.model
    end

    test "override only applies when conversation_id is passed", %{
      agent: agent,
      conversation: conv,
      p1: p1,
      p2: p2
    } do
      {:ok, _} =
        Providers.save_agent_provider_routing(agent.id, %{"default_provider_id" => p2.id})

      {:ok, _} =
        SwitchModel.execute(
          %{"conversation_id" => conv.id, "model" => p1.model, "reason" => "x"},
          %{}
        )

      # Without conversation_id, falls back to agent default.
      route_no_conv = Providers.effective_provider_route(agent.id, "channel")
      assert route_no_conv.provider.id == p2.id
    end
  end
end
