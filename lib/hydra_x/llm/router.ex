defmodule HydraX.LLM.Router do
  @moduledoc """
  Routes completions to the enabled provider and falls back to a local mock adapter.
  """

  alias HydraX.Runtime

  @spec complete(map()) :: {:ok, %{content: String.t(), provider: String.t()}} | {:error, term()}
  def complete(request) do
    provider = Runtime.enabled_provider()

    provider
    |> provider_module()
    |> apply(:complete, [Map.put(request, :provider_config, provider)])
  end

  defp provider_module(nil), do: HydraX.LLM.Providers.Mock
  defp provider_module(%{kind: "openai_compatible"}), do: HydraX.LLM.Providers.OpenAICompatible
  defp provider_module(%{kind: "anthropic"}), do: HydraX.LLM.Providers.Anthropic
end
