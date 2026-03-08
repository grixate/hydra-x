defmodule HydraX.LLM.Router do
  @moduledoc """
  Routes completions to the enabled provider and falls back to a local mock adapter.
  """

  alias HydraX.Runtime

  @spec complete(map()) :: {:ok, map()} | {:error, term()}
  def complete(request) do
    route =
      Runtime.effective_provider_route(request[:agent_id], request[:process_type] || "channel")

    providers = Enum.reject([route.provider | route.fallbacks], &is_nil/1)

    case providers do
      [] ->
        HydraX.LLM.Providers.Mock.complete(request)

      _ ->
        do_complete_with_fallbacks(providers, request)
    end
  end

  @doc """
  Stream a completion to the given caller process.

  Falls back to non-streaming `complete/1` if the provider doesn't support streaming,
  simulating a single-chunk delivery.
  """
  @spec complete_stream(map(), pid()) :: {:ok, reference()} | {:error, term()}
  def complete_stream(request, caller_pid) do
    route =
      Runtime.effective_provider_route(request[:agent_id], request[:process_type] || "channel")

    providers = Enum.reject([route.provider | route.fallbacks], &is_nil/1)

    case providers do
      [] ->
        {:error, :no_provider_configured}

      _ ->
        do_complete_stream_with_fallbacks(providers, request, caller_pid)
    end
  end

  defp do_complete_with_fallbacks([provider | rest], request) do
    enriched_request =
      request
      |> Map.put(:provider_config, provider)
      |> maybe_put_request_fn_from_env()

    case provider_module(provider).complete(enriched_request) do
      {:ok, response} ->
        {:ok, response}

      {:error, _reason} = error ->
        case rest do
          [] -> error
          _ -> do_complete_with_fallbacks(rest, request)
        end
    end
  end

  defp do_complete_stream_with_fallbacks([provider | rest], request, caller_pid) do
    mod = provider_module(provider)

    enriched_request =
      request
      |> Map.put(:provider_config, provider)
      |> maybe_put_request_fn_from_env()

    if function_exported?(mod, :complete_stream, 2) do
      case apply(mod, :complete_stream, [enriched_request, caller_pid]) do
        {:ok, ref} ->
          {:ok, ref}

        {:error, _reason} = error ->
          case rest do
            [] -> error
            _ -> do_complete_stream_with_fallbacks(rest, request, caller_pid)
          end
      end
    else
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

  defp maybe_put_request_fn_from_env(request) do
    case Application.get_env(:hydra_x, :provider_request_fn) do
      nil -> request
      request_fn -> Map.put(request, :request_fn, request_fn)
    end
  end

  defp provider_module(nil), do: HydraX.LLM.Providers.Mock
  defp provider_module(%{kind: "openai_compatible"}), do: HydraX.LLM.Providers.OpenAICompatible
  defp provider_module(%{kind: "anthropic"}), do: HydraX.LLM.Providers.Anthropic
end
