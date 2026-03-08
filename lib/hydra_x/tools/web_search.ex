defmodule HydraX.Tools.WebSearch do
  @behaviour HydraX.Tool

  @default_endpoint "https://duckduckgo.com/html/"
  @default_limit 5
  @max_excerpt 800

  @impl true
  def name, do: "web_search"

  @impl true
  def description, do: "Search the public web through a dedicated search endpoint"

  @impl true
  def tool_schema do
    %{
      name: "web_search",
      description:
        "Search the public web for recent or general information. Use this instead of raw http fetch when the user asks you to search or look something up.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "Search query text."
          },
          limit: %{
            type: "integer",
            description: "Optional result limit. Defaults to 5."
          }
        },
        required: ["query"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    request_fn = context[:request_fn] || (&Req.get/1)
    endpoint = context[:search_endpoint] || @default_endpoint

    with query when is_binary(query) <- params[:query] || params["query"],
         query <- String.trim(query),
         true <- query != "" or {:error, :missing_query},
         limit <- parse_limit(params[:limit] || params["limit"]),
         {:ok, response} <-
           request_fn.(
             url: endpoint,
             params: [q: query],
             headers: [{"user-agent", "Hydra-X/1.0"}],
             max_redirects: 3
           ),
         true <- response.status in 200..299 or {:error, {:search_error, response.status}} do
      body = body_to_string(response.body)

      {:ok,
       %{
         query: query,
         result_count: limit,
         results: parse_results(body, limit),
         excerpt: String.slice(body, 0, @max_excerpt)
       }}
    else
      nil -> {:error, :missing_query}
      false -> {:error, :missing_query}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_limit(nil), do: @default_limit
  defp parse_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 10)

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> min(value, 10)
      _ -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit

  defp body_to_string(body) when is_binary(body), do: body
  defp body_to_string(body), do: inspect(body)

  defp parse_results(body, limit) do
    Regex.scan(~r/<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/s, body)
    |> Enum.map(fn [_, url, title] ->
      %{
        title: strip_tags(title),
        url: decode_html(url)
      }
    end)
    |> Enum.take(limit)
  end

  defp strip_tags(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_html()
    |> String.trim()
  end

  defp decode_html(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end
end
