defmodule HydraX.LLM.Providers.OpenAICompatible do
  @behaviour HydraX.LLM.Provider

  @impl true
  def complete(%{provider_config: nil}) do
    HydraX.LLM.Providers.Mock.complete(%{messages: [], tool_results: [], bulletin: nil})
  end

  def complete(request) do
    provider = request.provider_config
    base_url = provider.base_url || "https://api.openai.com"

    case Req.post(
           url: Path.join(base_url, "/v1/chat/completions"),
           headers: auth_headers(provider.api_key),
           json: %{
             model: provider.model,
             messages: request.messages
           }
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, %{content: content, provider: provider.name}}

      {:ok, response} ->
        {:error, {:provider_error, response.status, response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp auth_headers(nil), do: []
  defp auth_headers(api_key), do: [{"authorization", "Bearer #{api_key}"}]
end
