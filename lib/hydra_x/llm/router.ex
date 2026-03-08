defmodule HydraX.LLM.Router do
  @moduledoc """
  Routes completions to the enabled provider and falls back to a local mock adapter.
  """

  alias HydraX.Runtime

  @spec complete(map()) :: {:ok, map()} | {:error, term()}
  def complete(request) do
    provider = Runtime.enabled_provider()

    provider
    |> provider_module()
    |> apply(:complete, [Map.put(request, :provider_config, provider)])
  end

  @doc """
  Stream a completion to the given caller process.

  Falls back to non-streaming `complete/1` if the provider doesn't support streaming,
  simulating a single-chunk delivery.
  """
  @spec complete_stream(map(), pid()) :: {:ok, reference()} | {:error, term()}
  def complete_stream(request, caller_pid) do
    provider = Runtime.enabled_provider()
    mod = provider_module(provider)
    enriched_request = Map.put(request, :provider_config, provider)

    if function_exported?(mod, :complete_stream, 2) do
      apply(mod, :complete_stream, [enriched_request, caller_pid])
    else
      # Fallback: simulate streaming with a single chunk
      ref = make_ref()

      Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
        case mod.complete(enriched_request) do
          {:ok, response} ->
            if response.content, do: send(caller_pid, {:chunk, ref, response.content})
            send(caller_pid, {:done, ref, response})

          {:error, reason} ->
            send(caller_pid, {:stream_error, ref, reason})
        end
      end)

      {:ok, ref}
    end
  end

  defp provider_module(nil), do: HydraX.LLM.Providers.Mock
  defp provider_module(%{kind: "openai_compatible"}), do: HydraX.LLM.Providers.OpenAICompatible
  defp provider_module(%{kind: "anthropic"}), do: HydraX.LLM.Providers.Anthropic
end
