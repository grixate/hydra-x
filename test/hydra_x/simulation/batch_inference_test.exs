defmodule HydraX.Simulation.Engine.BatchInferenceTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Engine.BatchInference
  alias HydraX.Simulation.Agent.Persona
  alias HydraX.Simulation.World.Event

  defp mock_llm_fn(response_action \\ "cautious_response") do
    fn _request ->
      {:ok, %{content: Jason.encode!(%{action: response_action, reasoning: "Test reasoning"})}}
    end
  end

  defp make_request(agent_id, tier, opts \\ []) do
    %{
      agent_id: agent_id,
      sim_id: "test_sim",
      tier: tier,
      event:
        Event.new(%{
          type: Keyword.get(opts, :event_type, :market_crash),
          stakes: 0.9,
          emotional_valence: :neutral,
          description: "Test event"
        }),
      persona: Keyword.get(opts, :persona, Persona.archetype(:cautious_cfo)),
      beliefs: MapSet.new(),
      modifier: nil
    }
  end

  describe "run/2" do
    test "dispatches requests and returns results" do
      requests = [
        make_request("agent_1", :cheap),
        make_request("agent_2", :cheap),
        make_request("agent_3", :frontier)
      ]

      results = BatchInference.run(requests, llm_fn: mock_llm_fn())

      assert length(results) == 3

      for {agent_id, result} <- results do
        assert agent_id in ["agent_1", "agent_2", "agent_3"]
        assert {:ok, decision} = result
        assert decision["action"] == "cautious_response"
      end
    end

    test "groups by tier with different concurrency" do
      # Create many cheap requests and few frontier
      cheap_requests = for i <- 1..10, do: make_request("cheap_#{i}", :cheap)
      frontier_requests = for i <- 1..3, do: make_request("frontier_#{i}", :frontier)

      all_requests = cheap_requests ++ frontier_requests

      results =
        BatchInference.run(all_requests,
          llm_fn: mock_llm_fn(),
          cheap_concurrency: 5,
          frontier_concurrency: 2
        )

      assert length(results) == 13
    end

    test "handles LLM errors gracefully" do
      error_fn = fn _request -> {:error, :rate_limited} end

      requests = [make_request("agent_1", :cheap)]
      results = BatchInference.run(requests, llm_fn: error_fn)

      assert [{agent_id, {:error, :rate_limited}}] = results
      assert agent_id == "agent_1"
    end

    test "handles timeout gracefully" do
      slow_fn = fn _request ->
        Process.sleep(5_000)
        {:ok, %{content: "{}"}}
      end

      requests = [make_request("agent_1", :cheap)]
      results = BatchInference.run(requests, llm_fn: slow_fn, timeout: 100)

      assert [{nil, {:error, :timeout}}] = results
    end

    test "parses JSON responses correctly" do
      json_fn = fn _request ->
        {:ok,
         %{
           content:
             Jason.encode!(%{
               action: "innovative_proposal",
               reasoning: "Market conditions favor innovation"
             })
         }}
      end

      requests = [make_request("agent_1", :cheap)]
      [{_id, {:ok, decision}}] = BatchInference.run(requests, llm_fn: json_fn)

      assert decision["action"] == "innovative_proposal"
      assert decision["reasoning"] == "Market conditions favor innovation"
    end

    test "extracts action from non-JSON text responses" do
      text_fn = fn _request ->
        {:ok, %{content: "I would take an aggressive stance given the competitive pressure."}}
      end

      requests = [make_request("agent_1", :cheap)]
      [{_id, {:ok, decision}}] = BatchInference.run(requests, llm_fn: text_fn)

      assert decision["action"] == "aggressive_response"
    end

    test "defaults to cautious_response for unrecognized text" do
      text_fn = fn _request ->
        {:ok, %{content: "I'm not sure what to do in this situation."}}
      end

      requests = [make_request("agent_1", :cheap)]
      [{_id, {:ok, decision}}] = BatchInference.run(requests, llm_fn: text_fn)

      assert decision["action"] == "cautious_response"
    end

    test "empty request list returns empty results" do
      results = BatchInference.run([], llm_fn: mock_llm_fn())
      assert results == []
    end
  end

  describe "execute_single/2" do
    test "builds prompt and calls LLM function" do
      test_pid = self()

      spy_fn = fn request ->
        send(test_pid, {:llm_called, request})
        {:ok, %{content: Jason.encode!(%{action: "seek_consensus"})}}
      end

      req = make_request("agent_1", :cheap)
      {:ok, decision} = BatchInference.execute_single(req, spy_fn)

      assert decision["action"] == "seek_consensus"

      assert_receive {:llm_called, llm_request}
      assert llm_request.process_type == "simulation"
      assert length(llm_request.messages) == 2
    end
  end
end
