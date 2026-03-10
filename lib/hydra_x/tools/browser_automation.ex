defmodule HydraX.Tools.BrowserAutomation do
  @behaviour HydraX.Tool

  alias HydraX.Safety.UrlGuard

  @max_excerpt 2_500
  @max_links 12
  @max_forms 8

  @impl true
  def name, do: "browser_automation"

  @impl true
  def description,
    do:
      "Fetch, inspect, preview, submit, and extract web content through a browser-style workflow"

  @impl true
  def safety_classification, do: "browser_automation"

  @impl true
  def tool_schema do
    %{
      name: "browser_automation",
      description:
        "Use a browser-style workflow for public web pages: fetch a page, inspect links, forms, headings, or tables, preview or submit a simple form, follow a link, capture a lightweight snapshot, or extract matching text. SSRF rules still apply.",
      input_schema: %{
        type: "object",
        properties: %{
          action: %{
            type: "string",
            description:
              "One of fetch_page, extract_links, inspect_forms, inspect_headings, extract_tables, preview_form_submission, click_link, submit_form, capture_snapshot, or extract_text"
          },
          url: %{type: "string", description: "The starting page URL"},
          link_text: %{
            type: "string",
            description: "For click_link, follow the first anchor containing this text"
          },
          href_contains: %{
            type: "string",
            description: "For click_link, follow the first anchor whose href contains this value"
          },
          link_index: %{
            type: "integer",
            description: "For click_link or extract_links, target a specific parsed link index"
          },
          method: %{
            type: "string",
            description: "For submit_form, GET or POST. Defaults to POST."
          },
          fields: %{
            type: "object",
            description: "For submit_form, form field values to send"
          },
          form_index: %{
            type: "integer",
            description: "For submit_form or inspect_forms, target a parsed form index"
          },
          form_action_contains: %{
            type: "string",
            description: "For submit_form, pick the first form whose action contains this value"
          },
          text_contains: %{
            type: "string",
            description: "For extract_text, return only text snippets containing this substring"
          }
        },
        required: ["action", "url"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    request_fn = context[:request_fn] || (&Req.request/1)
    allowlist = Map.get(context, :http_allowlist, HydraX.Config.http_allowlist())

    with action when is_binary(action) <- params[:action] || params["action"],
         url when is_binary(url) <- params[:url] || params["url"],
         {:ok, uri} <- UrlGuard.validate_outbound_url(url, allowlist: allowlist) do
      dispatch(action, uri, params, request_fn, allowlist)
    else
      nil -> {:error, :missing_url}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error

  def result_summary(%{action: action, title: title}) when is_binary(title),
    do: "#{action} #{title}"

  def result_summary(%{action: action, url: url}) when is_binary(url), do: "#{action} #{url}"
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp dispatch("fetch_page", uri, _params, request_fn, _allowlist) do
    fetch_page(uri, request_fn)
  end

  defp dispatch("extract_links", uri, params, request_fn, _allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn) do
      {:ok,
       %{
         action: "extract_links",
         url: page.url,
         title: page.title,
         links:
           filter_links(
             page.links,
             params[:link_text] || params["link_text"],
             params[:href_contains] || params["href_contains"],
             params[:link_index] || params["link_index"]
           )
       }}
    end
  end

  defp dispatch("inspect_forms", uri, params, request_fn, _allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn) do
      forms =
        case params[:form_index] || params["form_index"] do
          nil -> page.forms
          value -> Enum.filter(page.forms, &(&1.index == parse_index(value)))
        end

      {:ok,
       %{
         action: "inspect_forms",
         url: page.url,
         title: page.title,
         forms: forms
       }}
    end
  end

  defp dispatch("inspect_headings", uri, _params, request_fn, _allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn) do
      {:ok,
       %{
         action: "inspect_headings",
         url: page.url,
         title: page.title,
         headings: page.headings
       }}
    end
  end

  defp dispatch("extract_tables", uri, _params, request_fn, _allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn) do
      {:ok,
       %{
         action: "extract_tables",
         url: page.url,
         title: page.title,
         tables: page.tables
       }}
    end
  end

  defp dispatch("extract_text", uri, params, request_fn, _allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn) do
      snippets = extract_snippets(page.text, params[:text_contains] || params["text_contains"])
      {:ok, Map.put(page, :snippets, snippets)}
    end
  end

  defp dispatch("click_link", uri, params, request_fn, allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn),
         {:ok, href} <-
           find_link(
             page.links,
             params[:link_text] || params["link_text"],
             params[:href_contains] || params["href_contains"],
             params[:link_index] || params["link_index"]
           ),
         target <- URI.merge(uri, href),
         {:ok, safe_target} <-
           UrlGuard.validate_outbound_url(URI.to_string(target), allowlist: allowlist),
         {:ok, clicked} <- fetch_page(safe_target, request_fn) do
      {:ok,
       %{
         action: "click_link",
         url: clicked.url,
         from_url: page.url,
         followed_href: href,
         title: clicked.title,
         excerpt: clicked.excerpt,
         content_type: clicked.content_type,
         links: clicked.links,
         forms: clicked.forms
       }}
    end
  end

  defp dispatch("submit_form", uri, params, request_fn, allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn),
         {:ok, form} <-
           find_form(
             page.forms,
             params[:form_index] || params["form_index"],
             params[:form_action_contains] || params["form_action_contains"]
           ),
         target <- resolve_form_target(uri, form),
         {:ok, safe_target} <-
           UrlGuard.validate_outbound_url(URI.to_string(target), allowlist: allowlist),
         method <- normalized_method(params[:method] || params["method"] || form.method),
         req <-
           [
             method: if(method == "get", do: :get, else: :post),
             url: URI.to_string(safe_target),
             max_redirects: 3
           ]
           |> maybe_put_form(merged_form_fields(form, params[:fields] || params["fields"] || %{})),
         {:ok, response} <- request_fn.(req) do
      {:ok,
       %{
         action: "submit_form",
         url: URI.to_string(safe_target),
         method: String.upcase(method),
         form_index: form.index,
         form_action: form.action,
         status: response.status,
         excerpt: excerpt_body(response.body),
         content_type: header(response.headers || [], "content-type")
       }}
    end
  end

  defp dispatch("preview_form_submission", uri, params, request_fn, allowlist) do
    with {:ok, page} <- fetch_page(uri, request_fn),
         {:ok, form} <-
           find_form(
             page.forms,
             params[:form_index] || params["form_index"],
             params[:form_action_contains] || params["form_action_contains"]
           ),
         target <- resolve_form_target(uri, form),
         {:ok, safe_target} <-
           UrlGuard.validate_outbound_url(URI.to_string(target), allowlist: allowlist) do
      method = normalized_method(params[:method] || params["method"] || form.method)
      fields = merged_form_fields(form, params[:fields] || params["fields"] || %{})

      {:ok,
       %{
         action: "preview_form_submission",
         url: URI.to_string(safe_target),
         method: String.upcase(method),
         form_index: form.index,
         form_action: form.action,
         fields: fields
       }}
    end
  end

  defp dispatch(action, uri, _params, request_fn, _allowlist)
       when action in ["capture_snapshot", "capture_screenshot"] do
    with {:ok, page} <- fetch_page(uri, request_fn),
         {:ok, path} <- write_snapshot(page) do
      {:ok,
       %{
         action: "capture_snapshot",
         url: page.url,
         title: page.title,
         snapshot_path: path,
         content_type: "image/svg+xml"
       }}
    end
  end

  defp dispatch(_action, _uri, _params, _request_fn, _allowlist),
    do: {:error, :unsupported_action}

  defp fetch_page(uri, request_fn) do
    with {:ok, response} <-
           request_fn.(
             method: :get,
             url: URI.to_string(uri),
             headers: [{"user-agent", "Hydra-X BrowserAutomation/1.0"}],
             max_redirects: 3
           ) do
      body = body_to_string(response.body)
      text = plain_text(body)

      {:ok,
       %{
         action: "fetch_page",
         url: URI.to_string(uri),
         status: response.status,
         title: page_title(body),
         excerpt: String.slice(text, 0, @max_excerpt),
         text: text,
         content_type: header(response.headers || [], "content-type"),
         links: parse_links(body),
         forms: parse_forms(body),
         headings: parse_headings(body),
         tables: parse_tables(body)
       }}
    end
  end

  defp find_link(links, link_text, href_contains, link_index) do
    matched =
      case parse_index(link_index) do
        nil ->
          Enum.find(links, fn link ->
            cond do
              is_binary(link_text) and String.trim(link_text) != "" ->
                String.contains?(String.downcase(link.text), String.downcase(link_text))

              is_binary(href_contains) and String.trim(href_contains) != "" ->
                String.contains?(String.downcase(link.href), String.downcase(href_contains))

              true ->
                false
            end
          end)

        index ->
          Enum.find(links, &(&1.index == index))
      end

    case matched do
      nil -> {:error, :link_not_found}
      link -> {:ok, link.href}
    end
  end

  defp filter_links(links, link_text, href_contains, link_index) do
    case parse_index(link_index) do
      nil ->
        Enum.filter(links, fn link ->
          cond do
            is_binary(link_text) and String.trim(link_text) != "" ->
              String.contains?(String.downcase(link.text), String.downcase(link_text))

            is_binary(href_contains) and String.trim(href_contains) != "" ->
              String.contains?(String.downcase(link.href), String.downcase(href_contains))

            true ->
              true
          end
        end)

      index ->
        Enum.filter(links, &(&1.index == index))
    end
  end

  defp find_form(forms, form_index, action_contains) do
    matched =
      case parse_index(form_index) do
        nil ->
          Enum.find(forms, fn form ->
            cond do
              is_binary(action_contains) and String.trim(action_contains) != "" ->
                String.contains?(
                  String.downcase(form.action || ""),
                  String.downcase(action_contains)
                )

              true ->
                true
            end
          end)

        index ->
          Enum.find(forms, &(&1.index == index))
      end

    case matched do
      nil -> {:error, :form_not_found}
      form -> {:ok, form}
    end
  end

  defp maybe_put_form(req, fields) when map_size(fields) == 0, do: req
  defp maybe_put_form(req, fields), do: Keyword.put(req, :form, Map.new(fields))

  defp extract_snippets(text, nil), do: take_snippets(text)
  defp extract_snippets(text, ""), do: take_snippets(text)

  defp extract_snippets(text, needle) do
    text
    |> String.split(~r/\n+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&String.contains?(String.downcase(&1), String.downcase(needle)))
    |> Enum.take(6)
  end

  defp take_snippets(text) do
    text
    |> String.split(~r/\n+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(6)
  end

  defp body_to_string(body) when is_binary(body), do: body
  defp body_to_string(body), do: inspect(body)

  defp page_title(body) do
    case Regex.run(~r/<title[^>]*>(.*?)<\/title>/is, body) do
      [_, title] -> strip_tags(title)
      _ -> nil
    end
  end

  defp plain_text(body) do
    body
    |> String.replace(~r/<script.*?<\/script>/is, " ")
    |> String.replace(~r/<style.*?<\/style>/is, " ")
    |> strip_tags()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp parse_links(body) do
    Regex.scan(~r/<a[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/is, body)
    |> Enum.with_index()
    |> Enum.map(fn {[_, href, text], index} ->
      %{index: index, href: decode_html(href), text: strip_tags(text)}
    end)
    |> Enum.reject(fn link -> link.href == "" or link.text == "" end)
    |> Enum.take(@max_links)
  end

  defp parse_forms(body) do
    Regex.scan(~r/<form([^>]*)>(.*?)<\/form>/is, body)
    |> Enum.with_index()
    |> Enum.map(fn {[_, attrs, inner_html], index} ->
      %{
        index: index,
        method: parse_form_method(attrs),
        action: parse_form_action(attrs),
        fields: parse_form_fields(inner_html)
      }
    end)
    |> Enum.take(@max_forms)
  end

  defp parse_headings(body) do
    Regex.scan(~r/<h([1-6])[^>]*>(.*?)<\/h\1>/is, body)
    |> Enum.with_index()
    |> Enum.map(fn {[_, level, text], index} ->
      %{index: index, level: String.to_integer(level), text: strip_tags(text)}
    end)
    |> Enum.reject(&(&1.text == ""))
    |> Enum.take(16)
  end

  defp parse_tables(body) do
    Regex.scan(~r/<table[^>]*>(.*?)<\/table>/is, body)
    |> Enum.with_index()
    |> Enum.map(fn {[_, inner_html], index} ->
      rows =
        Regex.scan(~r/<tr[^>]*>(.*?)<\/tr>/is, inner_html)
        |> Enum.map(fn [_, row_html] ->
          Regex.scan(~r/<t[hd][^>]*>(.*?)<\/t[hd]>/is, row_html)
          |> Enum.map(fn [_, cell_html] -> strip_tags(cell_html) end)
        end)
        |> Enum.reject(&(&1 == []))

      {headers, data_rows} =
        case rows do
          [first | rest] -> {first, rest}
          [] -> {[], []}
        end

      %{index: index, headers: headers, rows: Enum.take(data_rows, 12)}
    end)
    |> Enum.reject(fn table -> table.headers == [] and table.rows == [] end)
    |> Enum.take(8)
  end

  defp parse_form_method(attrs) do
    case Regex.run(~r/method="([^"]+)"/i, attrs) do
      [_, method] -> normalized_method(method)
      _ -> "post"
    end
  end

  defp parse_form_action(attrs) do
    case Regex.run(~r/action="([^"]+)"/i, attrs) do
      [_, action] -> decode_html(action)
      _ -> nil
    end
  end

  defp parse_form_fields(inner_html) do
    Regex.scan(~r/<input([^>]*)>/i, inner_html)
    |> Enum.map(fn [_, attrs] ->
      %{
        name: parse_attr(attrs, "name"),
        type: parse_attr(attrs, "type") || "text",
        value: parse_attr(attrs, "value")
      }
    end)
    |> Enum.reject(&is_nil(&1.name))
  end

  defp parse_attr(attrs, key) do
    case Regex.run(~r/#{key}="([^"]+)"/i, attrs) do
      [_, value] -> decode_html(value)
      _ -> nil
    end
  end

  defp excerpt_body(body),
    do: body |> body_to_string() |> plain_text() |> String.slice(0, @max_excerpt)

  defp resolve_form_target(uri, %{action: nil}), do: uri
  defp resolve_form_target(uri, %{action: ""}), do: uri
  defp resolve_form_target(uri, %{action: action}), do: URI.merge(uri, action)

  defp merged_form_fields(form, overrides) do
    defaults =
      Enum.reduce(form.fields || [], %{}, fn field, acc ->
        if is_binary(field.name) and field.name != "" do
          Map.put(acc, field.name, field.value || "")
        else
          acc
        end
      end)

    Map.merge(defaults, Map.new(overrides))
  end

  defp normalized_method(method) do
    method
    |> to_string()
    |> String.downcase()
  end

  defp parse_index(nil), do: nil
  defp parse_index(index) when is_integer(index), do: index

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp write_snapshot(page) do
    root = Path.join(System.tmp_dir!(), "hydra-x-browser-snapshots")
    File.mkdir_p!(root)
    path = Path.join(root, "snapshot-#{System.unique_integer([:positive])}.svg")
    File.write!(path, snapshot_svg(page))
    {:ok, path}
  rescue
    error in File.Error -> {:error, {:snapshot_failed, Exception.message(error)}}
  end

  defp snapshot_svg(page) do
    title = xml_escape(page.title || page.url)
    subtitle = xml_escape(page.url)
    excerpt = xml_escape(String.slice(page.excerpt || "", 0, 420))

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="680" viewBox="0 0 1200 680">
      <rect width="1200" height="680" fill="#10161f"/>
      <rect x="32" y="32" width="1136" height="616" rx="24" fill="#182232" stroke="#2f3f55"/>
      <rect x="64" y="72" width="1072" height="56" rx="16" fill="#0f1724"/>
      <circle cx="92" cy="100" r="8" fill="#ff6b6b"/>
      <circle cx="118" cy="100" r="8" fill="#ffd166"/>
      <circle cx="144" cy="100" r="8" fill="#06d6a0"/>
      <text x="176" y="106" font-family="Menlo, monospace" font-size="20" fill="#b6c2d1">#{subtitle}</text>
      <text x="72" y="182" font-family="Helvetica, Arial, sans-serif" font-size="34" font-weight="700" fill="#f8fafc">#{title}</text>
      <text x="72" y="228" font-family="Helvetica, Arial, sans-serif" font-size="20" fill="#c7d2df">#{excerpt}</text>
      <text x="72" y="612" font-family="Menlo, monospace" font-size="18" fill="#7dd3fc">links #{length(page.links || [])} • forms #{length(page.forms || [])}</text>
    </svg>
    """
  end

  defp xml_escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp strip_tags(text) do
    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> decode_html()
    |> String.replace(~r/\s+/, " ")
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

  defp header(headers, key) do
    Enum.find_value(headers, fn
      {^key, value} -> value
      _ -> nil
    end)
  end
end
