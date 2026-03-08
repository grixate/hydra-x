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

    body =
      %{
        model: provider.model,
        max_tokens: 1_024,
        messages: messages
      }
      |> maybe_put_system(system_prompt)
      |> maybe_put_tools(request[:tools])

    case request_fn.(
           url: build_url(base_url, "/v1/messages"),
           headers: [
             {"x-api-key", provider.api_key},
             {"anthropic-version", "2023-06-01"}
           ],
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

  defp parse_response(%{"content" => content_blocks, "stop_reason" => stop_reason}, provider_name) do
    text =
      content_blocks
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("")
      |> case do
        "" -> nil
        text -> text
      end

    tool_calls =
      content_blocks
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn block ->
        %{
          id: block["id"],
          name: block["name"],
          arguments: block["input"] || %{}
        }
      end)
      |> case do
        [] -> nil
        calls -> calls
      end

    %{
      content: text,
      tool_calls: tool_calls,
      stop_reason: stop_reason,
      provider: provider_name
    }
  end

  defp parse_response(_body, provider_name) do
    %{content: nil, tool_calls: nil, stop_reason: "error", provider: provider_name}
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
      |> Enum.map(&format_message/1)

    {system_prompt, mapped_messages}
  end

  defp format_message(%{role: role, content: content}) when is_binary(content) do
    %{role: role, content: content}
  end

  defp format_message(%{role: role, content: content}) when is_list(content) do
    %{role: role, content: content}
  end

  defp format_message(msg), do: %{role: msg.role, content: msg.content}

  defp maybe_put_system(payload, ""), do: payload
  defp maybe_put_system(payload, system_prompt), do: Map.put(payload, :system, system_prompt)

  defp maybe_put_tools(payload, nil), do: payload
  defp maybe_put_tools(payload, []), do: payload

  defp maybe_put_tools(payload, tools) do
    formatted =
      Enum.map(tools, fn tool ->
        %{
          name: tool.name,
          description: tool.description,
          input_schema: tool.input_schema
        }
      end)

    Map.put(payload, :tools, formatted)
  end

  # -- Streaming --

  @impl true
  def complete_stream(%{provider_config: nil} = _request, _caller_pid) do
    {:error, :no_provider_configured}
  end

  def complete_stream(request, caller_pid) do
    provider = request.provider_config
    base_url = provider.base_url || "https://api.anthropic.com"
    {system_prompt, messages} = anthropic_messages(request.messages)
    request_options = request[:request_options] || []
    ref = make_ref()

    body =
      %{
        model: provider.model,
        max_tokens: 1_024,
        messages: messages,
        stream: true
      }
      |> maybe_put_system(system_prompt)
      |> maybe_put_tools(request[:tools])

    # Spawn a task to handle the streaming HTTP response
    Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
      stream_request(base_url, provider, body, request_options, caller_pid, ref)
    end)

    {:ok, ref}
  end

  defp stream_request(base_url, provider, body, request_options, caller_pid, ref) do
    # Use Req with into: fun to process SSE events as they arrive
    acc = %{text: "", tool_calls: [], current_tool: nil, stop_reason: nil}

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
      Req.post(
        url: build_url(base_url, "/v1/messages"),
        headers: [
          {"x-api-key", provider.api_key},
          {"anthropic-version", "2023-06-01"}
        ],
        json: body,
        into: into_fun,
        receive_timeout: Keyword.get(request_options, :receive_timeout, 60_000),
        retry: false
      )

    final_acc = Process.get(:stream_acc, acc)

    case result do
      {:ok, %{status: 200}} ->
        tool_calls =
          case final_acc.tool_calls do
            [] -> nil
            calls -> calls
          end

        content =
          case final_acc.text do
            "" -> nil
            text -> text
          end

        response = %{
          content: content,
          tool_calls: tool_calls,
          stop_reason: final_acc.stop_reason || "end_turn",
          provider: provider.name
        }

        send(caller_pid, {:done, ref, response})

      {:ok, resp} ->
        send(caller_pid, {:stream_error, ref, {:provider_error, resp.status, resp.body}})

      {:error, reason} ->
        send(caller_pid, {:stream_error, ref, reason})
    end
  end

  defp parse_sse_line("event: " <> _event_type, acc, _pid, _ref), do: acc

  defp parse_sse_line("data: " <> json_data, acc, caller_pid, ref) do
    case Jason.decode(json_data) do
      {:ok,
       %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}}} ->
        send(caller_pid, {:chunk, ref, text})
        %{acc | text: acc.text <> text}

      {:ok,
       %{
         "type" => "content_block_delta",
         "delta" => %{"type" => "input_json_delta", "partial_json" => partial}
       }} ->
        # Accumulate tool input JSON
        update_tool_input(acc, partial)

      {:ok,
       %{
         "type" => "content_block_start",
         "content_block" => %{"type" => "tool_use", "id" => id, "name" => name}
       }} ->
        %{acc | current_tool: %{id: id, name: name, input_json: ""}}

      {:ok, %{"type" => "content_block_stop"}} ->
        finalize_current_tool(acc)

      {:ok, %{"type" => "message_delta", "delta" => %{"stop_reason" => stop_reason}}} ->
        %{acc | stop_reason: stop_reason}

      _ ->
        acc
    end
  end

  defp parse_sse_line(_line, acc, _pid, _ref), do: acc

  defp update_tool_input(%{current_tool: nil} = acc, _partial), do: acc

  defp update_tool_input(%{current_tool: tool} = acc, partial) do
    %{acc | current_tool: %{tool | input_json: tool.input_json <> partial}}
  end

  defp finalize_current_tool(%{current_tool: nil} = acc), do: acc

  defp finalize_current_tool(%{current_tool: tool} = acc) do
    arguments =
      case Jason.decode(tool.input_json) do
        {:ok, args} when is_map(args) -> args
        _ -> %{}
      end

    completed_tool = %{id: tool.id, name: tool.name, arguments: arguments}
    %{acc | tool_calls: acc.tool_calls ++ [completed_tool], current_tool: nil}
  end

  defp build_url(base_url, path) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end
end
