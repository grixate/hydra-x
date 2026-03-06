defmodule HydraX.LLM.Providers.Anthropic do
  @behaviour HydraX.LLM.Provider

  @impl true
  def complete(%{provider_config: nil} = request), do: HydraX.LLM.Providers.Mock.complete(request)

  def complete(request) do
    provider = request.provider_config
    request_fn = request[:request_fn] || (&Req.post/1)
    base_url = provider.base_url || "https://api.anthropic.com"
    {system_prompt, messages} = anthropic_messages(request.messages)
    request_options = request[:request_options] || []

    case request_fn.(
           url: build_url(base_url, "/v1/messages"),
           headers: [
             {"x-api-key", provider.api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           json:
             %{
               model: provider.model,
               max_tokens: 1_024,
               messages: messages
             }
             |> maybe_put_system(system_prompt),
           receive_timeout: Keyword.get(request_options, :receive_timeout, 10_000),
           retry: Keyword.get(request_options, :retry, false)
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
    system_prompt =
      messages
      |> Enum.filter(&(&1.role == "system"))
      |> Enum.map(& &1.content)
      |> Enum.join("\n\n")

    mapped_messages =
      messages
      |> Enum.reject(&(&1.role == "system"))
      |> Enum.map(fn message -> %{role: message.role, content: message.content} end)

    {system_prompt, mapped_messages}
  end

  defp maybe_put_system(payload, ""), do: payload
  defp maybe_put_system(payload, system_prompt), do: Map.put(payload, :system, system_prompt)

  defp build_url(base_url, path) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end
end
