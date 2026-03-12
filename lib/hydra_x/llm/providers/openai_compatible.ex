defmodule HydraX.LLM.Providers.OpenAICompatible do
  @behaviour HydraX.LLM.Provider

  @impl true
  def capabilities do
    %{
      tool_calls: true,
      streaming: true,
      system_prompt: true,
      fallbacks: true,
      mock: false
    }
  end

  @impl true
  def complete(%{provider_config: nil} = request), do: HydraX.LLM.Providers.Mock.complete(request)

  def complete(request) do
    provider = request.provider_config
    request_fn = request[:request_fn] || (&Req.post/1)
    base_url = provider.base_url || "https://api.openai.com"
    request_options = request[:request_options] || []

    body =
      %{
        model: provider.model,
        messages: request.messages
      }
      |> maybe_put_tools(request[:tools])

    case request_fn.(
           url: build_url(base_url, "/v1/chat/completions"),
           headers: auth_headers(provider.api_key),
           json: body,
           receive_timeout: Keyword.get(request_options, :receive_timeout, 10_000),
           retry: Keyword.get(request_options, :retry, false)
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body, provider.name)}

      {:ok, response} ->
        {:error, {:provider_error, response.status, response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(
         %{"choices" => [%{"message" => message, "finish_reason" => finish_reason} | _]},
         provider_name
       ) do
    content = message["content"]

    tool_calls =
      case message["tool_calls"] do
        nil ->
          nil

        calls when is_list(calls) ->
          Enum.map(calls, fn call ->
            args =
              case call["function"]["arguments"] do
                args when is_binary(args) -> Jason.decode!(args)
                args when is_map(args) -> args
                _ -> %{}
              end

            %{
              id: call["id"],
              name: call["function"]["name"],
              arguments: args
            }
          end)
      end

    stop_reason =
      case finish_reason do
        "tool_calls" -> "tool_use"
        "stop" -> "end_turn"
        other -> other || "end_turn"
      end

    %{
      content: content,
      tool_calls: tool_calls,
      stop_reason: stop_reason,
      provider: provider_name
    }
  end

  defp parse_response(_body, provider_name) do
    %{content: nil, tool_calls: nil, stop_reason: "error", provider: provider_name}
  end

  defp maybe_put_tools(body, nil), do: body
  defp maybe_put_tools(body, []), do: body

  defp maybe_put_tools(body, tools) do
    formatted =
      Enum.map(tools, fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        }
      end)

    Map.put(body, :tools, formatted)
  end

  # -- Streaming --

  @impl true
  def complete_stream(%{provider_config: nil} = _request, _caller_pid) do
    {:error, :no_provider_configured}
  end

  def complete_stream(request, caller_pid) do
    provider = request.provider_config
    base_url = provider.base_url || "https://api.openai.com"
    request_options = request[:request_options] || []
    request_fn = request[:request_fn] || (&Req.post/1)
    ref = make_ref()

    body =
      %{
        model: provider.model,
        messages: request.messages,
        stream: true
      }
      |> maybe_put_tools(request[:tools])

    Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
      stream_request(base_url, provider, body, request_options, request_fn, caller_pid, ref)
    end)

    {:ok, ref}
  end

  @impl true
  def healthcheck(nil, _opts), do: HydraX.LLM.Providers.Mock.healthcheck(nil, [])

  def healthcheck(provider, opts) do
    request =
      %{
        provider_config: provider,
        messages: [
          %{role: "system", content: "You are a terse provider connectivity probe."},
          %{role: "user", content: "Reply with OK if you can read this request."}
        ],
        request_options:
          Keyword.get(opts, :request_options, receive_timeout: 10_000, retry: false)
      }
      |> maybe_put_request_fn(opts)

    case complete(request) do
      {:ok, response} ->
        {:ok,
         %{
           status: :ok,
           detail: "reachable via chat completions",
           sample: response.content,
           capabilities: capabilities()
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_request(base_url, provider, body, request_options, request_fn, caller_pid, ref) do
    acc = %{text: "", tool_calls: %{}, stop_reason: nil}

    into_fun = fn {:data, data}, {req, resp} ->
      new_acc =
        data
        |> String.split("\n", trim: true)
        |> Enum.reduce(Process.get(:stream_acc, acc), fn line, current_acc ->
          parse_sse_line(line, current_acc, caller_pid, ref)
        end)

      Process.put(:stream_acc, new_acc)
      {:cont, {req, resp}}
    end

    Process.put(:stream_acc, acc)

    result =
      request_fn.(
        url: build_url(base_url, "/v1/chat/completions"),
        headers: auth_headers(provider.api_key),
        json: body,
        into: into_fun,
        receive_timeout: Keyword.get(request_options, :receive_timeout, 60_000),
        retry: false
      )

    final_acc = Process.get(:stream_acc, acc)

    case result do
      {:ok, %{status: 200}} ->
        tool_calls = finalize_tool_calls(final_acc.tool_calls)

        content =
          case final_acc.text do
            "" -> nil
            text -> text
          end

        stop_reason =
          case final_acc.stop_reason do
            "tool_calls" -> "tool_use"
            "stop" -> "end_turn"
            other -> other || "end_turn"
          end

        response = %{
          content: content,
          tool_calls: tool_calls,
          stop_reason: stop_reason,
          provider: provider.name
        }

        send(caller_pid, {:done, ref, response})

      {:ok, resp} ->
        send(caller_pid, {:stream_error, ref, {:provider_error, resp.status, resp.body}})

      {:error, reason} ->
        send(caller_pid, {:stream_error, ref, reason})
    end
  end

  defp parse_sse_line("data: [DONE]", acc, _pid, _ref), do: acc

  defp parse_sse_line("data: " <> json_data, acc, caller_pid, ref) do
    case Jason.decode(json_data) do
      {:ok, %{"choices" => [%{"delta" => delta, "finish_reason" => finish_reason} | _]}} ->
        acc = if finish_reason, do: %{acc | stop_reason: finish_reason}, else: acc

        acc =
          case delta["content"] do
            nil ->
              acc

            "" ->
              acc

            text ->
              send(caller_pid, {:chunk, ref, text})
              %{acc | text: acc.text <> text}
          end

        # Accumulate tool call deltas
        acc =
          case delta["tool_calls"] do
            nil ->
              acc

            tool_deltas when is_list(tool_deltas) ->
              Enum.reduce(tool_deltas, acc, fn tc_delta, inner_acc ->
                idx = tc_delta["index"] || 0
                existing = Map.get(inner_acc.tool_calls, idx, %{id: nil, name: nil, args: ""})

                updated =
                  existing
                  |> maybe_update_tool_id(tc_delta)
                  |> maybe_update_tool_name(tc_delta)
                  |> maybe_update_tool_args(tc_delta)

                %{inner_acc | tool_calls: Map.put(inner_acc.tool_calls, idx, updated)}
              end)
          end

        acc

      _ ->
        acc
    end
  end

  defp parse_sse_line(_line, acc, _pid, _ref), do: acc

  defp maybe_update_tool_id(tool, %{"id" => id}) when is_binary(id), do: %{tool | id: id}
  defp maybe_update_tool_id(tool, _), do: tool

  defp maybe_update_tool_name(tool, %{"function" => %{"name" => name}}) when is_binary(name),
    do: %{tool | name: name}

  defp maybe_update_tool_name(tool, _), do: tool

  defp maybe_update_tool_args(tool, %{"function" => %{"arguments" => args}}) when is_binary(args),
    do: %{tool | args: tool.args <> args}

  defp maybe_update_tool_args(tool, _), do: tool

  defp finalize_tool_calls(tool_map) when map_size(tool_map) == 0, do: nil

  defp finalize_tool_calls(tool_map) do
    tool_map
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map(fn {_idx, tool} ->
      arguments =
        case Jason.decode(tool.args) do
          {:ok, args} when is_map(args) -> args
          _ -> %{}
        end

      %{id: tool.id, name: tool.name, arguments: arguments}
    end)
  end

  defp maybe_put_request_fn(request, opts) do
    case Keyword.get(opts, :request_fn) do
      nil -> request
      request_fn -> Map.put(request, :request_fn, request_fn)
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
