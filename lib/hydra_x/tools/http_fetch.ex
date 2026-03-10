defmodule HydraX.Tools.HttpFetch do
  @behaviour HydraX.Tool

  alias HydraX.Safety.UrlGuard

  @max_excerpt 4_000

  @impl true
  def name, do: "http_fetch"

  @impl true
  def description, do: "Fetch a public HTTP(S) resource after SSRF checks"

  @impl true
  def safety_classification, do: "network_read"

  @impl true
  def tool_schema do
    %{
      name: "http_fetch",
      description:
        "Fetch the contents of a public URL. Use this to retrieve web pages, API responses, or other HTTP resources the user asks about.",
      input_schema: %{
        type: "object",
        properties: %{
          url: %{
            type: "string",
            description: "The full URL to fetch (must be https:// or http://)"
          }
        },
        required: ["url"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    request_fn = context[:request_fn] || (&Req.get/1)
    allowlist = Map.get(context, :http_allowlist, HydraX.Config.http_allowlist())

    with url when is_binary(url) <- params[:url] || params["url"],
         {:ok, uri} <- UrlGuard.validate_outbound_url(url, allowlist: allowlist),
         {:ok, response} <- request_fn.(url: URI.to_string(uri), max_redirects: 3) do
      {:ok,
       %{
         url: URI.to_string(uri),
         status: response.status,
         excerpt: excerpt_body(response.body),
         content_type: header(response.headers || [], "content-type")
       }}
    else
      nil -> {:error, :missing_url}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(%{status: status, url: url}), do: "fetched #{url} (HTTP #{status})"
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp excerpt_body(body) when is_binary(body), do: String.slice(body, 0, @max_excerpt)

  defp excerpt_body(body) when is_map(body) or is_list(body),
    do: body |> Jason.encode!() |> String.slice(0, @max_excerpt)

  defp excerpt_body(body), do: inspect(body) |> String.slice(0, @max_excerpt)

  defp header(headers, key) do
    Enum.find_value(headers, fn
      {^key, value} -> value
      _ -> nil
    end)
  end
end
