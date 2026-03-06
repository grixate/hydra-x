defmodule HydraX.LLM.Providers.OpenAICompatible do
  @behaviour HydraX.LLM.Provider

  @impl true
  def complete(%{provider_config: nil} = request), do: HydraX.LLM.Providers.Mock.complete(request)

  def complete(request) do
    provider = request.provider_config
    request_fn = request[:request_fn] || (&Req.post/1)
    base_url = provider.base_url || "https://api.openai.com"
    request_options = request[:request_options] || []

    case request_fn.(
           url: build_url(base_url, "/v1/chat/completions"),
           headers: auth_headers(provider.api_key),
           json: %{
             model: provider.model,
             messages: request.messages
           },
           receive_timeout: Keyword.get(request_options, :receive_timeout, 10_000),
           retry: Keyword.get(request_options, :retry, false)
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

  defp build_url(base_url, path) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end
end
