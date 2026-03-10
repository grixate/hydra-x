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
        "Use a browser-style workflow for public web pages: fetch a page, inspect links, forms, headings, tables, images, scripts, or metadata, preview or submit a simple form, follow a link, capture a lightweight snapshot, or extract matching text. A prior session can be passed back in to preserve cookies and navigation history. SSRF rules still apply.",
      input_schema: %{
        type: "object",
        properties: %{
          action: %{
            type: "string",
            description:
              "One of fetch_page, extract_links, inspect_forms, inspect_headings, inspect_images, inspect_meta, inspect_scripts, inspect_structured_data, extract_tables, preview_form_submission, click_link, submit_form, capture_snapshot, or extract_text"
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
          },
          session: %{
            type: "object",
            description:
              "Optional browser session object returned by a previous browser_automation call. Preserves cookies and navigation history across steps."
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
    session = normalize_session(params[:session] || params["session"])

    with action when is_binary(action) <- params[:action] || params["action"],
         url when is_binary(url) <- params[:url] || params["url"],
         {:ok, uri} <- UrlGuard.validate_outbound_url(url, allowlist: allowlist) do
      dispatch(action, uri, params, request_fn, allowlist, session)
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

  defp dispatch("fetch_page", uri, _params, request_fn, _allowlist, session) do
    fetch_page(uri, request_fn, session)
  end

  defp dispatch("extract_links", uri, params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
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
           ),
         session: page.session
       }}
    end
  end

  defp dispatch("inspect_forms", uri, params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
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
         forms: forms,
         session: page.session
       }}
    end
  end

  defp dispatch("inspect_headings", uri, _params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      {:ok,
       %{
         action: "inspect_headings",
         url: page.url,
         title: page.title,
         headings: page.headings,
         session: page.session
       }}
    end
  end

  defp dispatch("inspect_images", uri, _params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      {:ok,
       %{
         action: "inspect_images",
         url: page.url,
         title: page.title,
         images: page.images,
         session: page.session
       }}
    end
  end

  defp dispatch("inspect_meta", uri, _params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      {:ok,
       %{
         action: "inspect_meta",
         url: page.url,
         title: page.title,
         meta: page.meta,
         session: page.session
       }}
    end
  end

  defp dispatch("inspect_scripts", uri, _params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      {:ok,
       %{
         action: "inspect_scripts",
         url: page.url,
         title: page.title,
         scripts: page.scripts,
         session: page.session
       }}
    end
  end

  defp dispatch("inspect_structured_data", uri, _params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      {:ok,
       %{
         action: "inspect_structured_data",
         url: page.url,
         title: page.title,
         structured_data: page.structured_data,
         session: page.session
       }}
    end
  end

  defp dispatch("extract_tables", uri, _params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      {:ok,
       %{
         action: "extract_tables",
         url: page.url,
         title: page.title,
         tables: page.tables,
         session: page.session
       }}
    end
  end

  defp dispatch("extract_text", uri, params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      snippets = extract_snippets(page.text, params[:text_contains] || params["text_contains"])
      {:ok, Map.put(page, :snippets, snippets)}
    end
  end

  defp dispatch("click_link", uri, params, request_fn, allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session),
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
         {:ok, clicked} <- fetch_page(safe_target, request_fn, page.session) do
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
         forms: clicked.forms,
         session: clicked.session
       }}
    end
  end

  defp dispatch("submit_form", uri, params, request_fn, allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session),
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
             headers: session_headers(page.session),
             max_redirects: 3
           ]
           |> maybe_put_form(merged_form_fields(form, params[:fields] || params["fields"] || %{})),
         {:ok, response} <- request_fn.(req) do
      next_session =
        page.session
        |> merge_response_cookies(response.headers || [])
        |> update_session_history(URI.to_string(safe_target))

      {:ok,
       %{
         action: "submit_form",
         url: URI.to_string(safe_target),
         method: String.upcase(method),
         form_index: form.index,
         form_action: form.action,
         status: response.status,
         excerpt: excerpt_body(response.body),
         content_type: header(response.headers || [], "content-type"),
         session: next_session
       }}
    end
  end

  defp dispatch("preview_form_submission", uri, params, request_fn, allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session),
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
         fields: fields,
         session: page.session
       }}
    end
  end

  defp dispatch(action, uri, _params, request_fn, _allowlist, session)
       when action in ["capture_snapshot", "capture_screenshot"] do
    with {:ok, page} <- fetch_page(uri, request_fn, session),
         {:ok, path} <- write_snapshot(page) do
      {:ok,
       %{
         action: "capture_snapshot",
         url: page.url,
         title: page.title,
         snapshot_path: path,
         content_type: "image/svg+xml",
         link_count: length(page.links),
         heading_count: length(page.headings),
         image_count: length(page.images),
         session: page.session
       }}
    end
  end

  defp dispatch(_action, _uri, _params, _request_fn, _allowlist, _session),
    do: {:error, :unsupported_action}

  defp fetch_page(uri, request_fn, session) do
    with {:ok, response} <-
           request_fn.(
             method: :get,
             url: URI.to_string(uri),
             headers:
               [{"user-agent", "Hydra-X BrowserAutomation/1.0"}] ++ session_headers(session),
             max_redirects: 3
           ) do
      body = body_to_string(response.body)
      text = plain_text(body)
      next_session =
        session
        |> merge_response_cookies(response.headers || [])
        |> update_session_history(URI.to_string(uri))

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
         images: parse_images(body),
         meta: parse_meta(body),
         scripts: parse_scripts(body),
         structured_data: parse_structured_data(body),
         tables: parse_tables(body),
         session: next_session
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

  defp normalize_session(nil), do: %{cookies: %{}, history: []}

  defp normalize_session(session) when is_map(session) do
    cookies =
      session
      |> Map.get(:cookies, Map.get(session, "cookies", %{}))
      |> normalize_cookies()

    history =
      session
      |> Map.get(:history, Map.get(session, "history", []))
      |> normalize_history()

    %{cookies: cookies, history: history}
  end

  defp normalize_session(_other), do: %{cookies: %{}, history: []}

  defp normalize_cookies(cookies) when is_map(cookies) do
    cookies
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Map.new()
  end

  defp normalize_cookies(_cookies), do: %{}

  defp normalize_history(history) when is_list(history) do
    history
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(-12)
  end

  defp normalize_history(_history), do: []

  defp session_headers(%{cookies: cookies}) when map_size(cookies) > 0 do
    cookie_value =
      cookies
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join("; ", fn {key, value} -> "#{key}=#{value}" end)

    [{"cookie", cookie_value}]
  end

  defp session_headers(_session), do: []

  defp merge_response_cookies(session, headers) do
    new_cookies =
      headers
      |> Enum.flat_map(fn
        {"set-cookie", value} -> List.wrap(parse_set_cookie(value))
        {"Set-Cookie", value} -> List.wrap(parse_set_cookie(value))
        _ -> []
      end)
      |> Map.new()

    %{session | cookies: Map.merge(session.cookies, new_cookies)}
  end

  defp parse_set_cookie(value) when is_binary(value) do
    case value |> String.split(";", parts: 2) |> List.first() |> String.split("=", parts: 2) do
      [name, cookie_value] when name != "" -> {String.trim(name), String.trim(cookie_value)}
      _ -> nil
    end
  end

  defp parse_set_cookie(_value), do: nil

  defp update_session_history(session, url) when is_binary(url) do
    history =
      case List.last(session.history) do
        ^url -> session.history
        _ -> session.history ++ [url]
      end
      |> Enum.take(-12)

    %{session | history: history}
  end

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

  defp parse_images(body) do
    Regex.scan(~r/<img([^>]*)>/i, body)
    |> Enum.with_index()
    |> Enum.map(fn {[_, attrs], index} ->
      %{
        index: index,
        src: parse_attr(attrs, "src"),
        alt: parse_attr(attrs, "alt"),
        width: parse_dimension(parse_attr(attrs, "width")),
        height: parse_dimension(parse_attr(attrs, "height"))
      }
    end)
    |> Enum.reject(&is_nil(&1.src))
    |> Enum.take(16)
  end

  defp parse_meta(body) do
    tags =
      Regex.scan(~r/<meta([^>]*)>/i, body)
      |> Enum.reduce(%{}, fn [_, attrs], acc ->
        key =
          parse_attr(attrs, "property") ||
            parse_attr(attrs, "name") ||
            parse_attr(attrs, "http-equiv")

        value = parse_attr(attrs, "content")

        if is_binary(key) and key != "" and is_binary(value) and value != "" do
          Map.put_new(acc, key, value)
        else
          acc
        end
      end)

    canonical =
      case Regex.run(~r/<link[^>]*rel="canonical"[^>]*href="([^"]+)"/i, body) do
        [_, href] -> decode_html(href)
        _ -> nil
      end

    %{
      description: Map.get(tags, "description"),
      canonical_url: canonical,
      open_graph:
        tags
        |> Enum.filter(fn {key, _value} -> String.starts_with?(String.downcase(key), "og:") end)
        |> Map.new(),
      twitter:
        tags
        |> Enum.filter(fn {key, _value} -> String.starts_with?(String.downcase(key), "twitter:") end)
        |> Map.new(),
      all: tags
    }
  end

  defp parse_scripts(body) do
    Regex.scan(~r/<script([^>]*)>(.*?)<\/script>/is, body)
    |> Enum.with_index()
    |> Enum.map(fn {[_, attrs, content], index} ->
      type = parse_attr(attrs, "type") || "text/javascript"
      src = parse_attr(attrs, "src")
      body_excerpt =
        content
        |> strip_tags()
        |> String.slice(0, 180)

      %{
        index: index,
        src: src,
        type: type,
        inline: is_nil(src),
        excerpt: body_excerpt
      }
    end)
    |> Enum.reject(fn script ->
      is_nil(script.src) and script.excerpt in [nil, ""]
    end)
    |> Enum.take(24)
  end

  defp parse_structured_data(body) do
    Regex.scan(~r/<script([^>]*)type="application\/ld\+json"([^>]*)>(.*?)<\/script>/is, body)
    |> Enum.with_index()
    |> Enum.map(fn {match, index} ->
      content = List.last(match)

      parsed =
        case Jason.decode(String.trim(content)) do
          {:ok, value} when is_map(value) -> value
          {:ok, value} when is_list(value) -> value
          _ -> nil
        end

      summary =
        case parsed do
          %{"@type" => type} -> to_string(type)
          [%{"@type" => type} | _] -> to_string(type)
          _ -> "structured data"
        end

      %{
        index: index,
        summary: summary,
        data: parsed || String.slice(String.trim(content), 0, 240)
      }
    end)
    |> Enum.take(12)
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

  defp parse_dimension(nil), do: nil

  defp parse_dimension(value) do
    case Integer.parse(value) do
      {dimension, _rest} -> dimension
      :error -> nil
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
