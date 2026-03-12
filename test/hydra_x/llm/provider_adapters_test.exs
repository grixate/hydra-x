defmodule HydraX.LLM.ProviderAdaptersTest do
  use ExUnit.Case, async: true

  alias HydraX.LLM.Providers.{Anthropic, OpenAICompatible}
  alias HydraX.Runtime.ProviderConfig

  test "openai compatible provider posts chat completions payload" do
    provider = %ProviderConfig{
      name: "OpenAI Test",
      kind: "openai_compatible",
      base_url: "https://example.test",
      api_key: "secret",
      model: "gpt-test"
    }

    request_fn = fn opts ->
      assert opts[:url] == "https://example.test/v1/chat/completions"
      assert {"authorization", "Bearer secret"} in opts[:headers]
      assert opts[:json][:model] == "gpt-test"
      assert [%{role: "user", content: "hello"}] = opts[:json][:messages]

      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => "hi"}, "finish_reason" => "stop"}]}
       }}
    end

    assert {:ok, %{content: "hi", provider: "OpenAI Test"}} =
             OpenAICompatible.complete(%{
               provider_config: provider,
               messages: [%{role: "user", content: "hello"}],
               request_fn: request_fn
             })
  end

  test "openai compatible adapter exposes capabilities and healthcheck" do
    provider = %ProviderConfig{
      name: "OpenAI Test",
      kind: "openai_compatible",
      base_url: "https://example.test",
      api_key: "secret",
      model: "gpt-test"
    }

    request_fn = fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => "OK"}, "finish_reason" => "stop"}]}
       }}
    end

    assert OpenAICompatible.capabilities().tool_calls
    assert OpenAICompatible.capabilities().streaming

    assert {:ok, %{status: :ok, capabilities: %{tool_calls: true}, detail: detail}} =
             OpenAICompatible.healthcheck(provider, request_fn: request_fn)

    assert detail =~ "chat completions"
  end

  test "openai compatible streaming adapter emits chunks and final response via request_fn" do
    provider = %ProviderConfig{
      name: "OpenAI Stream Test",
      kind: "openai_compatible",
      base_url: "https://example.test",
      api_key: "secret",
      model: "gpt-stream-test"
    }

    request_fn = fn opts ->
      into = Keyword.fetch!(opts, :into)

      {:cont, state} =
        into.(
          {:data,
           "data: {\"choices\":[{\"delta\":{\"content\":\"Hello \"},\"finish_reason\":null}]}\n\n"},
          {%{}, %{}}
        )

      {:cont, state} =
        into.(
          {:data,
           "data: {\"choices\":[{\"delta\":{\"content\":\"stream\"},\"finish_reason\":null}]}\n\n"},
          state
        )

      {:cont, _state} =
        into.(
          {:data,
           "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"},
          state
        )

      {:ok, %{status: 200}}
    end

    assert {:ok, ref} =
             OpenAICompatible.complete_stream(
               %{
                 provider_config: provider,
                 messages: [%{role: "user", content: "hello"}],
                 request_fn: request_fn
               },
               self()
             )

    assert_receive {:chunk, ^ref, "Hello "}
    assert_receive {:chunk, ^ref, "stream"}
    assert_receive {:done, ^ref, %{content: "Hello stream", provider: "OpenAI Stream Test"}}
  end

  test "anthropic provider preserves system prompt separately" do
    provider = %ProviderConfig{
      name: "Anthropic Test",
      kind: "anthropic",
      base_url: "https://anthropic.test",
      api_key: "secret",
      model: "claude-test"
    }

    request_fn = fn opts ->
      assert opts[:url] == "https://anthropic.test/v1/messages"
      assert {"x-api-key", "secret"} in opts[:headers]
      assert opts[:json][:model] == "claude-test"
      assert opts[:json][:system] == "You are terse."
      assert [%{role: "user", content: "hello"}] = opts[:json][:messages]

      {:ok,
       %{
         status: 200,
         body: %{"content" => [%{"type" => "text", "text" => "hi"}], "stop_reason" => "end_turn"}
       }}
    end

    assert {:ok, %{content: "hi", provider: "Anthropic Test"}} =
             Anthropic.complete(%{
               provider_config: provider,
               messages: [
                 %{role: "system", content: "You are terse."},
                 %{role: "user", content: "hello"}
               ],
               request_fn: request_fn
             })
  end

  test "anthropic adapter exposes capabilities and healthcheck" do
    provider = %ProviderConfig{
      name: "Anthropic Test",
      kind: "anthropic",
      base_url: "https://anthropic.test",
      api_key: "secret",
      model: "claude-test"
    }

    request_fn = fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{"content" => [%{"type" => "text", "text" => "OK"}], "stop_reason" => "end_turn"}
       }}
    end

    assert Anthropic.capabilities().tool_calls
    assert Anthropic.capabilities().streaming

    assert {:ok, %{status: :ok, capabilities: %{tool_calls: true}, detail: detail}} =
             Anthropic.healthcheck(provider, request_fn: request_fn)

    assert detail =~ "messages API"
  end

  test "anthropic streaming adapter emits chunks and final response via request_fn" do
    provider = %ProviderConfig{
      name: "Anthropic Stream Test",
      kind: "anthropic",
      base_url: "https://anthropic.test",
      api_key: "secret",
      model: "claude-stream-test"
    }

    request_fn = fn opts ->
      into = Keyword.fetch!(opts, :into)

      {:cont, state} =
        into.(
          {:data,
           "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello \"}}\n\n"},
          {%{}, %{}}
        )

      {:cont, state} =
        into.(
          {:data,
           "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"anthropic\"}}\n\n"},
          state
        )

      {:cont, _state} =
        into.(
          {:data,
           "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n"},
          state
        )

      {:ok, %{status: 200}}
    end

    assert {:ok, ref} =
             Anthropic.complete_stream(
               %{
                 provider_config: provider,
                 messages: [%{role: "user", content: "hello"}],
                 request_fn: request_fn
               },
               self()
             )

    assert_receive {:chunk, ^ref, "Hello "}
    assert_receive {:chunk, ^ref, "anthropic"}
    assert_receive {:done, ^ref, %{content: "Hello anthropic", provider: "Anthropic Stream Test"}}
  end
end
