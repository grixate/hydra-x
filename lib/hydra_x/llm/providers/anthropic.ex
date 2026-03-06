defmodule HydraX.LLM.Providers.Anthropic do
  @behaviour HydraX.LLM.Provider

  @impl true
  def complete(%{provider_config: nil}) do
    HydraX.LLM.Providers.Mock.complete(%{messages: [], tool_results: [], bulletin: nil})
  end

  def complete(request) do
    provider = request.provider_config
    base_url = provider.base_url || "https://api.anthropic.com"

    case Req.post(
           url: Path.join(base_url, "/v1/messages"),
           headers: [
             {"x-api-key", provider.api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           json: %{
             model: provider.model,
             max_tokens: 1_024,
             messages: anthropic_messages(request.messages)
           }
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => content} | _]}}} ->
        {:ok, %{content: content, provider: provider.name}}

      {:ok, response} ->
        {:error, {:provider_error, response.status, response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp anthropic_messages(messages) do
    Enum.reject(messages, &(&1.role == "system"))
  end
end
