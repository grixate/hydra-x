defmodule HydraX.LLM.Providers.Mock do
  @behaviour HydraX.LLM.Provider

  @impl true
  def capabilities do
    %{
      tool_calls: false,
      streaming: false,
      system_prompt: true,
      fallbacks: false,
      mock: true
    }
  end

  @impl true
  def complete(request) do
    # Support injected mock responses for testing tool-calling loops
    case request[:mock_response] do
      nil -> complete_default(request)
      response -> {:ok, response}
    end
  end

  defp complete_default(request) do
    last_user =
      request.messages
      |> Enum.reverse()
      |> Enum.find_value("", fn
        %{role: "user", content: content} when is_binary(content) -> content
        _ -> nil
      end)

    bulletin = Map.get(request, :bulletin)

    content =
      [
        if(bulletin not in [nil, ""], do: "Bulletin: #{bulletin}"),
        "Mock response: #{last_user}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    {:ok,
     %{
       content: content,
       tool_calls: nil,
       stop_reason: "end_turn",
       provider: "mock"
     }}
  end

  @impl true
  def healthcheck(_provider, _opts) do
    {:ok,
     %{
       status: :ok,
       detail: "local mock provider available",
       capabilities: capabilities()
     }}
  end
end
