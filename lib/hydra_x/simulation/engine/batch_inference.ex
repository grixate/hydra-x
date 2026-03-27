defmodule HydraX.Simulation.Engine.BatchInference do
  @moduledoc """
  Concurrent batched LLM dispatch for simulation ticks.

  Collects all LLM requests from a single tick, groups them by tier,
  and dispatches concurrently with backpressure using Task.async_stream.

  Tier concurrency limits:
  - cheap (DeepSeek/Ollama): 20 concurrent
  - frontier (Anthropic/OpenAI): 5 concurrent
  """

  alias HydraX.Simulation.Engine.PromptBuilder

  @cheap_concurrency 20
  @frontier_concurrency 5
  @call_timeout_ms 15_000

  @doc """
  Run a batch of LLM requests concurrently, respecting rate limits.
  Groups by tier for efficient dispatch.

  Each request is a map with:
  - :agent_id, :sim_id, :tier, :event, :persona, :beliefs, :modifier
  - Optionally: :relationships, :counterpart_id (for negotiations)

  Returns a list of {agent_id, result} tuples where result is {:ok, decision} or {:error, reason}.
  """
  @spec run([map()], keyword()) :: [{String.t(), {:ok, map()} | {:error, term()}}]
  def run(requests, opts \\ []) do
    llm_fn = Keyword.get(opts, :llm_fn, &default_llm_call/1)

    requests
    |> Enum.group_by(fn req -> req.tier end)
    |> Enum.flat_map(fn {tier, tier_requests} ->
      max_concurrency =
        case tier do
          :cheap -> Keyword.get(opts, :cheap_concurrency, @cheap_concurrency)
          :frontier -> Keyword.get(opts, :frontier_concurrency, @frontier_concurrency)
          _ -> @cheap_concurrency
        end

      timeout = Keyword.get(opts, :timeout, @call_timeout_ms)

      tier_requests
      |> Task.async_stream(
        fn req -> {req.agent_id, execute_single(req, llm_fn)} end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {agent_id, result}} -> {agent_id, result}
        {:exit, :timeout} -> {nil, {:error, :timeout}}
      end)
    end)
  end

  @doc """
  Execute a single LLM request, building the prompt and calling the provider.
  """
  def execute_single(req, llm_fn) do
    messages = PromptBuilder.build(req)

    llm_request = %{
      messages: messages,
      agent_id: req[:agent_id],
      sim_id: req[:sim_id],
      process_type: "simulation",
      tier: req[:tier],
      max_tokens: max_tokens_for_tier(req[:tier])
    }

    case llm_fn.(llm_request) do
      {:ok, response} ->
        decision = parse_llm_response(response, req[:tier])
        {:ok, decision}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_llm_call(request) do
    HydraX.LLM.Router.complete(request)
  end

  defp max_tokens_for_tier(:cheap), do: 200
  defp max_tokens_for_tier(:frontier), do: 500
  defp max_tokens_for_tier(_), do: 200

  defp parse_llm_response(response, tier) do
    content = response[:content] || response["content"] || ""

    # Try to extract a structured decision from the LLM response
    case Jason.decode(content) do
      {:ok, parsed} ->
        Map.put(parsed, "tier", to_string(tier))

      {:error, _} ->
        # If not JSON, extract action from natural language
        action = extract_action_from_text(content)
        %{"action" => action, "reasoning" => content, "tier" => to_string(tier)}
    end
  end

  @action_keywords %{
    "aggressive" => "aggressive_response",
    "cautious" => "cautious_response",
    "innovate" => "innovative_proposal",
    "consensus" => "seek_consensus",
    "defer" => "defer_to_authority",
    "wait" => "wait_and_observe",
    "public" => "public_statement",
    "negotiate" => "private_negotiation",
    "nothing" => "do_nothing"
  }

  defp extract_action_from_text(text) do
    text_lower = String.downcase(text)

    matched =
      Enum.find(@action_keywords, fn {keyword, _action} ->
        String.contains?(text_lower, keyword)
      end)

    case matched do
      {_keyword, action} -> action
      nil -> "cautious_response"
    end
  end
end
