defmodule HydraX.Tools.BrowserAutomation do
  @behaviour HydraX.Tool

  alias HydraX.Runtime.Helpers
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
              "One of fetch_page, extract_links, inspect_forms, inspect_headings, inspect_images, inspect_meta, inspect_scripts, inspect_structured_data, extract_tables, extract_elements, preview_form_submission, click_link, submit_form, capture_snapshot, or extract_text"
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
          selector: %{
            type: "string",
            description:
              "Optional simple CSS-like selector for tag, #id, .class, or tag.class forms. Used by extract_text, extract_elements, click_link, and form selection."
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
    browser_runtime = browser_runtime(context)
    allowlist = Map.get(context, :http_allowlist, HydraX.Config.http_allowlist())
    session = normalize_session(params[:session] || params["session"])

    with action when is_binary(action) <- params[:action] || params["action"],
         url when is_binary(url) <- params[:url] || params["url"],
         {:ok, uri} <- UrlGuard.validate_outbound_url(url, allowlist: allowlist) do
      dispatch_with_browser(action, uri, params, request_fn, allowlist, session, browser_runtime)
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

  defp dispatch_with_browser(action, uri, params, request_fn, allowlist, session, browser_runtime) do
    case dispatch_browser(action, uri, params, allowlist, session, browser_runtime) do
      {:fallback, _reason} -> dispatch(action, uri, params, request_fn, allowlist, session)
      result -> result
    end
  end

  defp dispatch_browser(_action, _uri, _params, _allowlist, _session, nil),
    do: {:fallback, :browser_runtime_not_configured}

  defp dispatch_browser("fetch_page", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok, Map.put(page, :action, "fetch_page")}
    end
  end

  defp dispatch_browser("extract_links", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "extract_links",
         backend: "browser",
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

  defp dispatch_browser("inspect_forms", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      forms =
        case params[:form_index] || params["form_index"] do
          nil -> page.forms
          value -> Enum.filter(page.forms, &(&1.index == parse_index(value)))
        end

      {:ok,
       %{
         action: "inspect_forms",
         backend: "browser",
         url: page.url,
         title: page.title,
         forms: forms,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("inspect_headings", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "inspect_headings",
         backend: "browser",
         url: page.url,
         title: page.title,
         headings: page.headings,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("inspect_images", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "inspect_images",
         backend: "browser",
         url: page.url,
         title: page.title,
         images: page.images,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("inspect_meta", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "inspect_meta",
         backend: "browser",
         url: page.url,
         title: page.title,
         meta: page.meta,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("inspect_scripts", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "inspect_scripts",
         backend: "browser",
         url: page.url,
         title: page.title,
         scripts: page.scripts,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("inspect_structured_data", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "inspect_structured_data",
         backend: "browser",
         url: page.url,
         title: page.title,
         structured_data: page.structured_data,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("extract_tables", uri, params, _allowlist, session, runtime) do
    with {:ok, page} <- browser_fetch_page(uri, params, session, runtime) do
      {:ok,
       %{
         action: "extract_tables",
         backend: "browser",
         url: page.url,
         title: page.title,
         tables: page.tables,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("extract_elements", uri, params, _allowlist, session, runtime) do
    with {:ok, result} <- run_browser_action("extract_elements", uri, params, session, runtime),
         {:ok, page} <- normalize_browser_page(result, "extract_elements", uri, session),
         {:ok, selector} <- parse_selector(params[:selector] || params["selector"]) do
      elements =
        normalize_browser_elements(browser_value(result, :elements)) ||
          find_elements(page.body, selector)

      {:ok,
       %{
         action: "extract_elements",
         backend: "browser",
         url: page.url,
         title: page.title,
         selector: selector.raw,
         elements: elements,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("extract_text", uri, params, _allowlist, session, runtime) do
    with {:ok, result} <- run_browser_action("extract_text", uri, params, session, runtime),
         {:ok, page} <- normalize_browser_page(result, "extract_text", uri, session) do
      snippets =
        normalize_browser_snippets(browser_value(result, :snippets)) ||
          case Helpers.blank_to_nil(params[:selector] || params["selector"]) do
            nil ->
              extract_snippets(page.text, params[:text_contains] || params["text_contains"])

            selector_value ->
              with {:ok, selector} <- parse_selector(selector_value) do
                page.body
                |> find_elements(selector)
                |> Enum.map(&(&1.text || ""))
                |> Enum.join("\n")
                |> extract_snippets(params[:text_contains] || params["text_contains"])
              else
                _ -> []
              end
          end

      {:ok,
       page
       |> Map.put(:action, "extract_text")
       |> Map.put(:backend, "browser")
       |> Map.put(:selector, params[:selector] || params["selector"])
       |> Map.put(:snippets, snippets)}
    end
  end

  defp dispatch_browser("click_link", uri, params, _allowlist, session, runtime) do
    with {:ok, result} <- run_browser_action("click_link", uri, params, session, runtime),
         {:ok, page} <- normalize_browser_page(result, "click_link", uri, session) do
      {:ok,
       %{
         action: "click_link",
         backend: "browser",
         url: page.url,
         from_url: browser_value(result, :from_url) || URI.to_string(uri),
         followed_href: browser_value(result, :followed_href),
         title: page.title,
         excerpt: page.excerpt,
         content_type: page.content_type,
         links: page.links,
         forms: page.forms,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("submit_form", uri, params, _allowlist, session, runtime) do
    with {:ok, result} <- run_browser_action("submit_form", uri, params, session, runtime),
         {:ok, page} <- normalize_browser_page(result, "submit_form", uri, session) do
      {:ok,
       %{
         action: "submit_form",
         backend: "browser",
         url: page.url,
         method:
           browser_value(result, :method) ||
             normalized_method(params[:method] || params["method"] || "post") |> String.upcase(),
         form_index: browser_value(result, :form_index),
         form_action: browser_value(result, :form_action),
         status: page.status,
         excerpt: page.excerpt,
         content_type: page.content_type,
         session: page.session
       }}
    end
  end

  defp dispatch_browser("preview_form_submission", uri, params, _allowlist, session, runtime) do
    with {:ok, result} <-
           run_browser_action("preview_form_submission", uri, params, session, runtime),
         fields when is_map(fields) <- normalize_browser_fields(browser_value(result, :fields)) do
      {:ok,
       %{
         action: "preview_form_submission",
         backend: "browser",
         url: browser_value(result, :url) || URI.to_string(uri),
         method:
           browser_value(result, :method) ||
             normalized_method(params[:method] || params["method"] || "post") |> String.upcase(),
         form_index: browser_value(result, :form_index),
         form_action: browser_value(result, :form_action),
         fields: fields,
         session: normalize_browser_session(browser_value(result, :session), session)
       }}
    else
      {:fallback, reason} -> {:fallback, reason}
      nil -> {:error, :browser_runtime_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_browser(action, uri, params, _allowlist, session, runtime)
       when action in ["capture_snapshot", "capture_screenshot"] do
    with {:ok, result} <- run_browser_action(action, uri, params, session, runtime),
         screenshot_path when is_binary(screenshot_path) <-
           browser_value(result, :screenshot_path),
         {:ok, page} <- normalize_browser_page(result, action, uri, session) do
      {:ok,
       %{
         action:
           if(action == "capture_screenshot", do: "capture_screenshot", else: "capture_snapshot"),
         backend: "browser",
         url: page.url,
         title: page.title,
         snapshot_path: screenshot_path,
         content_type:
           if browser_value(result, :content_type) in ["image/png", "image/jpeg", "image/webp"] do
             browser_value(result, :content_type)
           else
             "image/png"
           end,
         link_count: length(page.links),
         heading_count: length(page.headings),
         image_count: length(page.images),
         session: page.session
       }}
    else
      {:fallback, reason} -> {:fallback, reason}
      nil -> {:error, :browser_runtime_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_browser(_action, _uri, _params, _allowlist, _session, _runtime),
    do: {:fallback, :browser_action_not_supported}

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

  defp dispatch("extract_elements", uri, params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session),
         {:ok, selector} <- parse_selector(params[:selector] || params["selector"]) do
      {:ok,
       %{
         action: "extract_elements",
         url: page.url,
         title: page.title,
         selector: selector.raw,
         elements: find_elements(page.body, selector),
         session: page.session
       }}
    end
  end

  defp dispatch("extract_text", uri, params, request_fn, _allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session) do
      snippets =
        case Helpers.blank_to_nil(params[:selector] || params["selector"]) do
          nil ->
            extract_snippets(page.text, params[:text_contains] || params["text_contains"])

          selector_value ->
            with {:ok, selector} <- parse_selector(selector_value) do
              page.body
              |> find_elements(selector)
              |> Enum.map(&(&1.text || ""))
              |> Enum.join("\n")
              |> extract_snippets(params[:text_contains] || params["text_contains"])
            else
              _ -> []
            end
        end

      {:ok,
       page
       |> Map.put(:selector, params[:selector] || params["selector"])
       |> Map.put(:snippets, snippets)}
    end
  end

  defp dispatch("click_link", uri, params, request_fn, allowlist, session) do
    with {:ok, page} <- fetch_page(uri, request_fn, session),
         {:ok, href} <-
           find_link(
             page.body,
             page.links,
             params[:selector] || params["selector"],
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
             page.body,
             page.forms,
             params[:selector] || params["selector"],
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
             page.body,
             page.forms,
             params[:selector] || params["selector"],
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
         body: body,
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

  defp find_link(body, links, selector, link_text, href_contains, link_index) do
    matched =
      case parse_index(link_index) do
        nil ->
          case Helpers.blank_to_nil(selector) do
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

            selector_value ->
              with {:ok, parsed_selector} <- parse_selector(selector_value) do
                body
                |> find_elements(parsed_selector)
                |> Enum.find(fn element ->
                  element.tag == "a" and is_binary(element.attrs["href"]) and
                    element.attrs["href"] != ""
                end)
                |> case do
                  nil -> nil
                  element -> %{href: element.attrs["href"], text: element.text}
                end
              else
                _ -> nil
              end
          end

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

  defp find_form(_body, forms, selector, form_index, action_contains) do
    matched =
      case parse_index(form_index) do
        nil ->
          case Helpers.blank_to_nil(selector) do
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

            selector_value ->
              with {:ok, parsed_selector} <- parse_selector(selector_value) do
                Enum.find(forms, &selector_match_form?(&1, parsed_selector))
              else
                _ -> nil
              end
          end

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

    browser_state =
      session
      |> Map.get(:browser_state, Map.get(session, "browser_state"))
      |> normalize_browser_state()

    %{cookies: cookies, history: history}
    |> maybe_put_browser_state(browser_state)
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

  defp normalize_browser_state(nil), do: nil

  defp normalize_browser_state(state) when is_map(state) do
    state
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_browser_state(_state), do: nil

  defp maybe_put_browser_state(session, nil), do: session

  defp maybe_put_browser_state(session, browser_state),
    do: Map.put(session, :browser_state, browser_state)

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

  defp update_session_history(session, _url), do: session

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
        id: parse_attr(attrs, "id"),
        classes: parse_classes(attrs),
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
        |> Enum.filter(fn {key, _value} ->
          String.starts_with?(String.downcase(key), "twitter:")
        end)
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

  defp parse_classes(attrs) do
    attrs
    |> parse_attr("class")
    |> case do
      nil -> []
      value -> String.split(value, ~r/\s+/, trim: true)
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

  defp browser_runtime(context) do
    context[:browser_runtime_fn] ||
      Application.get_env(:hydra_x, :browser_automation_runtime_fn) ||
      (&default_browser_runtime/1)
  end

  defp browser_fetch_page(uri, params, session, runtime) do
    with {:ok, result} <- run_browser_action("fetch_page", uri, params, session, runtime) do
      normalize_browser_page(result, "fetch_page", uri, session)
    end
  end

  defp run_browser_action(action, uri, params, session, runtime) when is_function(runtime, 1) do
    payload = %{
      action: action,
      url: URI.to_string(uri),
      selector: params[:selector] || params["selector"],
      link_text: params[:link_text] || params["link_text"],
      href_contains: params[:href_contains] || params["href_contains"],
      link_index: params[:link_index] || params["link_index"],
      method: params[:method] || params["method"],
      fields: params[:fields] || params["fields"] || %{},
      form_index: params[:form_index] || params["form_index"],
      form_action_contains: params[:form_action_contains] || params["form_action_contains"],
      text_contains: params[:text_contains] || params["text_contains"],
      session: session
    }

    case runtime.(payload) do
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, :browser_unavailable} -> {:fallback, :browser_unavailable}
      {:error, {:browser_runtime_failed, _message} = reason} -> {:fallback, reason}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :browser_runtime_invalid}
    end
  end

  defp normalize_browser_page(result, action, uri, previous_session) when is_map(result) do
    html = browser_value(result, :html) || browser_value(result, :body) || ""
    text = browser_value(result, :text) || plain_text(html)
    url = browser_value(result, :url) || URI.to_string(uri)

    {:ok,
     %{
       action: action,
       backend: "browser",
       url: url,
       status: browser_value(result, :status) || 200,
       title: browser_value(result, :title) || page_title(html),
       excerpt: browser_value(result, :excerpt) || String.slice(text, 0, @max_excerpt),
       body: html,
       text: text,
       content_type: browser_value(result, :content_type) || "text/html",
       links: normalize_browser_links(browser_value(result, :links)) || parse_links(html),
       forms: normalize_browser_forms(browser_value(result, :forms)) || parse_forms(html),
       headings:
         normalize_browser_headings(browser_value(result, :headings)) || parse_headings(html),
       images: normalize_browser_images(browser_value(result, :images)) || parse_images(html),
       meta: normalize_browser_meta(browser_value(result, :meta)) || parse_meta(html),
       scripts: normalize_browser_scripts(browser_value(result, :scripts)) || parse_scripts(html),
       structured_data:
         normalize_browser_structured_data(browser_value(result, :structured_data)) ||
           parse_structured_data(html),
       tables: normalize_browser_tables(browser_value(result, :tables)) || parse_tables(html),
       session: normalize_browser_session(browser_value(result, :session), previous_session, url)
     }}
  end

  defp normalize_browser_session(nil, previous_session, current_url) do
    previous_session
    |> normalize_session()
    |> update_session_history(current_url)
  end

  defp normalize_browser_session(raw_session, previous_session, current_url) do
    base = normalize_session(raw_session)
    previous = normalize_session(previous_session)

    base
    |> Map.update(:cookies, previous.cookies, &Map.merge(previous.cookies, &1))
    |> Map.update(:history, previous.history, fn history ->
      history
      |> Kernel.++(base.history)
      |> Enum.uniq()
      |> Enum.take(-12)
    end)
    |> update_session_history(current_url)
  end

  defp normalize_browser_session(raw_session, previous_session) do
    normalize_browser_session(raw_session, previous_session, nil)
  end

  defp browser_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp default_browser_runtime(payload) do
    script_path =
      Path.expand(
        Path.join(["..", "..", "..", "priv", "scripts", "browser_automation.mjs"]),
        __DIR__
      )

    command =
      case browser_runtime_command() do
        nil -> ["node", script_path]
        parts -> parts ++ [script_path]
      end

    payload_path =
      Path.join(
        System.tmp_dir!(),
        "hydra-x-browser-payload-#{System.unique_integer([:positive])}.json"
      )

    try do
      File.write!(payload_path, Jason.encode!(payload))

      case command do
        [executable | args] ->
          case System.cmd(executable, args ++ [payload_path], stderr_to_stdout: true) do
            {output, 0} -> parse_browser_runtime_output(output)
            failure -> browser_runtime_failure(failure)
          end

        _ ->
          {:error, :browser_runtime_invalid}
      end
    rescue
      error in [ErlangError, File.Error] ->
        if match?(%ErlangError{original: :enoent}, error) do
          {:error, :browser_unavailable}
        else
          {:error, {:browser_runtime_failed, Exception.message(error)}}
        end
    after
      File.rm(payload_path)
    end
  end

  defp parse_browser_runtime_output(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, %{"ok" => true, "result" => result}} when is_map(result) ->
        {:ok, result}

      {:ok, %{"ok" => false, "error" => error}} ->
        browser_runtime_failure(error)

      _ ->
        {:error, :browser_runtime_invalid}
    end
  end

  defp browser_runtime_command do
    case System.get_env("HYDRA_X_BROWSER_AUTOMATION_COMMAND") do
      nil -> nil
      "" -> nil
      command -> OptionParser.split(command)
    end
  end

  defp browser_runtime_failure({output, _status}) when is_binary(output) do
    browser_runtime_failure(output)
  end

  defp browser_runtime_failure(error) when is_binary(error) do
    downcased = String.downcase(error)

    cond do
      String.contains?(downcased, "cannot find package 'playwright'") ->
        {:error, :browser_unavailable}

      String.contains?(downcased, "cannot find module 'playwright'") ->
        {:error, :browser_unavailable}

      String.contains?(downcased, "browser executable") ->
        {:error, :browser_unavailable}

      true ->
        {:error, {:browser_runtime_failed, String.slice(String.trim(error), 0, 300)}}
    end
  end

  defp browser_runtime_failure(%{"code" => code, "message" => message})
       when is_binary(code) and is_binary(message) do
    if code == "browser_unavailable" do
      {:error, :browser_unavailable}
    else
      {:error, {:browser_runtime_failed, message}}
    end
  end

  defp browser_runtime_failure(_other), do: {:error, :browser_runtime_invalid}

  defp normalize_browser_links(nil), do: nil

  defp normalize_browser_links(links) when is_list(links) do
    links
    |> Enum.with_index()
    |> Enum.map(fn {link, index} ->
      %{
        index: browser_value(link, :index) || index,
        href: browser_value(link, :href) || "",
        text: browser_value(link, :text) || ""
      }
    end)
    |> Enum.reject(fn link -> link.href == "" or link.text == "" end)
  end

  defp normalize_browser_links(_links), do: nil

  defp normalize_browser_forms(nil), do: nil

  defp normalize_browser_forms(forms) when is_list(forms) do
    forms
    |> Enum.with_index()
    |> Enum.map(fn {form, index} ->
      %{
        index: browser_value(form, :index) || index,
        id: browser_value(form, :id),
        classes: List.wrap(browser_value(form, :classes)),
        method: normalized_method(browser_value(form, :method) || "post"),
        action: browser_value(form, :action),
        fields:
          browser_value(form, :fields)
          |> normalize_browser_form_fields()
      }
    end)
  end

  defp normalize_browser_forms(_forms), do: nil

  defp normalize_browser_form_fields(nil), do: []

  defp normalize_browser_form_fields(fields) when is_list(fields) do
    Enum.map(fields, fn field ->
      %{
        name: browser_value(field, :name),
        type: browser_value(field, :type) || "text",
        value: browser_value(field, :value)
      }
    end)
  end

  defp normalize_browser_form_fields(_fields), do: []

  defp normalize_browser_headings(nil), do: nil

  defp normalize_browser_headings(headings) when is_list(headings) do
    headings
    |> Enum.with_index()
    |> Enum.map(fn {heading, index} ->
      %{
        index: browser_value(heading, :index) || index,
        level: browser_value(heading, :level) || 1,
        text: browser_value(heading, :text) || ""
      }
    end)
    |> Enum.reject(&(&1.text == ""))
  end

  defp normalize_browser_headings(_headings), do: nil

  defp normalize_browser_images(nil), do: nil

  defp normalize_browser_images(images) when is_list(images) do
    images
    |> Enum.with_index()
    |> Enum.map(fn {image, index} ->
      %{
        index: browser_value(image, :index) || index,
        src: browser_value(image, :src),
        alt: browser_value(image, :alt),
        width: browser_value(image, :width),
        height: browser_value(image, :height)
      }
    end)
    |> Enum.reject(&is_nil(&1.src))
  end

  defp normalize_browser_images(_images), do: nil

  defp normalize_browser_meta(nil), do: nil

  defp normalize_browser_meta(meta) when is_map(meta) do
    %{
      description: browser_value(meta, :description),
      canonical_url: browser_value(meta, :canonical_url),
      open_graph: normalize_browser_fields(browser_value(meta, :open_graph)),
      twitter: normalize_browser_fields(browser_value(meta, :twitter)),
      all: normalize_browser_fields(browser_value(meta, :all))
    }
  end

  defp normalize_browser_meta(_meta), do: nil

  defp normalize_browser_scripts(nil), do: nil

  defp normalize_browser_scripts(scripts) when is_list(scripts) do
    scripts
    |> Enum.with_index()
    |> Enum.map(fn {script, index} ->
      %{
        index: browser_value(script, :index) || index,
        src: browser_value(script, :src),
        type: browser_value(script, :type) || "text/javascript",
        inline: browser_value(script, :inline) || false,
        excerpt: browser_value(script, :excerpt) || ""
      }
    end)
  end

  defp normalize_browser_scripts(_scripts), do: nil

  defp normalize_browser_structured_data(nil), do: nil

  defp normalize_browser_structured_data(entries) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      %{
        index: browser_value(entry, :index) || index,
        summary: browser_value(entry, :summary) || "structured data",
        data: browser_value(entry, :data)
      }
    end)
  end

  defp normalize_browser_structured_data(_entries), do: nil

  defp normalize_browser_tables(nil), do: nil

  defp normalize_browser_tables(tables) when is_list(tables) do
    tables
    |> Enum.with_index()
    |> Enum.map(fn {table, index} ->
      %{
        index: browser_value(table, :index) || index,
        headers: List.wrap(browser_value(table, :headers)),
        rows: List.wrap(browser_value(table, :rows))
      }
    end)
  end

  defp normalize_browser_tables(_tables), do: nil

  defp normalize_browser_elements(nil), do: nil

  defp normalize_browser_elements(elements) when is_list(elements) do
    elements
    |> Enum.with_index()
    |> Enum.map(fn {element, index} ->
      %{
        index: browser_value(element, :index) || index,
        tag: browser_value(element, :tag) || "div",
        text: browser_value(element, :text) || "",
        attrs: normalize_browser_fields(browser_value(element, :attrs))
      }
    end)
  end

  defp normalize_browser_elements(_elements), do: nil

  defp normalize_browser_snippets(nil), do: nil

  defp normalize_browser_snippets(snippets) when is_list(snippets),
    do: Enum.map(snippets, &to_string/1)

  defp normalize_browser_snippets(_snippets), do: nil

  defp normalize_browser_fields(nil), do: %{}

  defp normalize_browser_fields(fields) when is_map(fields) do
    fields
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_browser_fields(_fields), do: %{}

  defp parse_index(nil), do: nil
  defp parse_index(index) when is_integer(index), do: index

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp parse_selector(nil), do: {:error, :missing_selector}
  defp parse_selector(""), do: {:error, :missing_selector}

  defp parse_selector(selector) when is_binary(selector) do
    selector = String.trim(selector)

    case Regex.named_captures(
           ~r/^(?<tag>[a-z0-9_-]+)?(?<id>#[a-zA-Z0-9_-]+)?(?<classes>(\.[a-zA-Z0-9_-]+)*)$/u,
           selector
         ) do
      %{"tag" => tag, "id" => id, "classes" => classes} ->
        {:ok,
         %{
           raw: selector,
           tag: blank_to_nil(tag),
           id: id |> String.trim_leading("#") |> blank_to_nil(),
           classes:
             Regex.scan(~r/\.([a-zA-Z0-9_-]+)/u, classes, capture: :all_but_first)
             |> List.flatten()
         }}

      _ ->
        {:error, :unsupported_selector}
    end
  end

  defp parse_selector(_selector), do: {:error, :unsupported_selector}

  defp find_elements(body, selector) do
    candidate_tags =
      case selector.tag do
        nil ->
          ~w(a article button div form h1 h2 h3 h4 h5 h6 label li p section span td th)

        tag ->
          [String.downcase(tag)]
      end

    candidate_tags
    |> Enum.flat_map(&scan_elements_for_tag(body, &1))
    |> Enum.with_index()
    |> Enum.map(fn {element, index} -> Map.put(element, :index, index) end)
    |> Enum.filter(&selector_match?(&1, selector))
    |> Enum.reject(&(&1.text == "" and map_size(&1.attrs) == 0))
    |> Enum.take(24)
  end

  defp scan_elements_for_tag(body, tag) do
    Regex.scan(~r/<#{tag}([^>]*)>(.*?)<\/#{tag}>/is, body)
    |> Enum.map(fn [_, attrs, inner_html] ->
      %{
        tag: tag,
        text: strip_tags(inner_html),
        attrs: extract_element_attrs(attrs)
      }
    end)
  end

  defp extract_element_attrs(attrs) do
    for key <- ~w(id class href src action name type role aria-label),
        value = parse_attr(attrs, key),
        value not in [nil, ""],
        into: %{} do
      {key, value}
    end
  end

  defp selector_match?(element, %{tag: tag, id: id, classes: classes}) do
    tag_ok = is_nil(tag) or element.tag == String.downcase(tag)
    id_ok = is_nil(id) or element.attrs["id"] == id

    element_classes =
      element.attrs["class"]
      |> case do
        nil -> []
        value -> String.split(value, ~r/\s+/, trim: true)
      end

    classes_ok = Enum.all?(classes, &(&1 in element_classes))
    tag_ok and id_ok and classes_ok
  end

  defp selector_match_form?(form, %{tag: tag, id: id, classes: classes}) do
    tag_ok = is_nil(tag) or String.downcase(tag) == "form"
    id_ok = is_nil(id) or form.id == id
    classes_ok = Enum.all?(classes, &(&1 in (form.classes || [])))
    tag_ok and id_ok and classes_ok
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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
