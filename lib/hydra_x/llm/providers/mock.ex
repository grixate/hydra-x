defmodule HydraX.LLM.Providers.Mock do
  @behaviour HydraX.LLM.Provider

  @impl true
  def complete(request) do
    last_user =
      request.messages
      |> Enum.reverse()
      |> Enum.find_value("", fn
        %{role: "user", content: content} -> content
        _ -> nil
      end)

    tool_context =
      request.tool_results
      |> Enum.map(fn result ->
        case result do
          %{tool: "memory_recall", results: results} when is_list(results) and results != [] ->
            "Relevant memory:\n" <>
              Enum.map_join(results, "\n", fn item -> "- [#{item.type}] #{item.content}" end)

          %{tool: "memory_save", content: content, type: type} ->
            "Saved memory [#{type}]: #{content}"

          %{tool: tool, reply: reply} ->
            "#{tool}: #{reply}"

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    content =
      [
        if(request.bulletin not in [nil, ""], do: "Bulletin: #{request.bulletin}"),
        if(tool_context != "", do: tool_context),
        "Mock response: #{last_user}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    {:ok, %{content: content, provider: "mock"}}
  end
end
