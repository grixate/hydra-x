defmodule HydraX.Tools.ToolSafetyTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  alias HydraX.Tools.{
    BrowserAutomation,
    HttpFetch,
    ShellCommand,
    WebSearch,
    WorkspaceList,
    WorkspacePatch,
    WorkspaceRead,
    WorkspaceWrite
  }

  test "workspace listing stays inside the agent workspace" do
    agent = create_agent()
    File.mkdir_p!(Path.join(agent.workspace_root, "memory"))
    File.write!(Path.join(agent.workspace_root, "memory/notes.md"), "Hydra notes")

    assert {:ok, result} =
             WorkspaceList.execute(%{path: "memory"}, %{workspace_root: agent.workspace_root})

    assert result.path == "memory"
    assert Enum.any?(result.entries, &(&1.name == "notes.md" and &1.type == "file"))

    assert {:error, :path_outside_workspace} =
             WorkspaceList.execute(%{path: "../secrets"}, %{workspace_root: agent.workspace_root})
  end

  test "workspace reads stay inside the agent workspace" do
    agent = create_agent()
    soul_path = Path.join(agent.workspace_root, "SOUL.md")
    File.write!(soul_path, "Hydra soul")

    assert {:ok, result} =
             WorkspaceRead.execute(%{path: "SOUL.md"}, %{workspace_root: agent.workspace_root})

    assert result.path == "SOUL.md"
    assert result.excerpt =~ "Hydra soul"

    assert {:error, :path_outside_workspace} =
             WorkspaceRead.execute(%{path: "../secrets.txt"}, %{
               workspace_root: agent.workspace_root
             })
  end

  test "workspace writes stay inside the agent workspace" do
    agent = create_agent()

    assert {:ok, result} =
             WorkspaceWrite.execute(
               %{path: "memory/new-note.md", content: "Hydra write test"},
               %{workspace_root: agent.workspace_root}
             )

    assert result.path == "memory/new-note.md"
    assert File.read!(Path.join(agent.workspace_root, "memory/new-note.md")) == "Hydra write test"

    assert {:error, :path_outside_workspace} =
             WorkspaceWrite.execute(
               %{path: "../outside.txt", content: "nope"},
               %{workspace_root: agent.workspace_root}
             )
  end

  test "workspace patch performs targeted edits inside the workspace" do
    agent = create_agent()
    path = Path.join(agent.workspace_root, "memory/patch-note.md")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "alpha\nbeta\nbeta\n")

    assert {:ok, result} =
             WorkspacePatch.execute(
               %{path: "memory/patch-note.md", search: "beta", replace: "gamma"},
               %{workspace_root: agent.workspace_root}
             )

    assert result.path == "memory/patch-note.md"
    assert result.replacements == 1
    assert File.read!(path) == "alpha\ngamma\nbeta\n"

    assert {:ok, result} =
             WorkspacePatch.execute(
               %{
                 path: "memory/patch-note.md",
                 search: "beta",
                 replace: "delta",
                 replace_all: true
               },
               %{workspace_root: agent.workspace_root}
             )

    assert result.replacements == 1
    assert File.read!(path) == "alpha\ngamma\ndelta\n"
  end

  test "workspace patch blocks traversal and missing search text" do
    agent = create_agent()

    assert {:error, :path_outside_workspace} =
             WorkspacePatch.execute(
               %{path: "../outside.txt", search: "a", replace: "b"},
               %{workspace_root: agent.workspace_root}
             )

    file_path = Path.join(agent.workspace_root, "memory/no-match.md")
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, "unchanged")

    assert {:error, :search_not_found} =
             WorkspacePatch.execute(
               %{path: "memory/no-match.md", search: "missing", replace: "value"},
               %{workspace_root: agent.workspace_root}
             )
  end

  test "http fetch blocks localhost style targets before issuing a request" do
    request_fn = fn _opts ->
      send(self(), :request_attempted)
      {:ok, %{status: 200, body: "should not happen", headers: []}}
    end

    assert {:error, :blocked_host} =
             HttpFetch.execute(%{url: "http://localhost:4000/health"}, %{request_fn: request_fn})

    refute_received :request_attempted
  end

  test "http fetch enforces an optional host allowlist" do
    previous = System.get_env("HYDRA_X_HTTP_ALLOWLIST")
    System.put_env("HYDRA_X_HTTP_ALLOWLIST", "example.com")

    on_exit(fn ->
      if previous do
        System.put_env("HYDRA_X_HTTP_ALLOWLIST", previous)
      else
        System.delete_env("HYDRA_X_HTTP_ALLOWLIST")
      end
    end)

    request_fn = fn _opts ->
      send(self(), :request_attempted)
      {:ok, %{status: 200, body: "should not happen", headers: []}}
    end

    assert {:error, :host_not_allowlisted} =
             HttpFetch.execute(%{url: "https://not-example.test/data"}, %{request_fn: request_fn})

    refute_received :request_attempted
  end

  test "web search returns parsed search results through the dedicated endpoint" do
    request_fn = fn _opts ->
      {:ok,
       %{
         status: 200,
         body:
           ~s(<html><body><a class="result__a" href="https://example.com/a">Example A</a><a class="result__a" href="https://example.com/b">Example B</a></body></html>),
         headers: []
       }}
    end

    assert {:ok, result} =
             WebSearch.execute(%{query: "hydra x", limit: 2}, %{request_fn: request_fn})

    assert result.query == "hydra x"

    assert [%{title: "Example A", url: "https://example.com/a"}, %{title: "Example B"}] =
             result.results
  end

  test "browser automation fetches and follows public page links" do
    request_fn = fn opts ->
      case {opts[:method], opts[:url]} do
        {:get, "https://example.com/start"} ->
          {:ok,
           %{
             status: 200,
             body:
               ~s(<html><head><title>Start Page</title></head><body><a href="/next">Read more</a><p>Hydra browser entry</p></body></html>),
             headers: [{"content-type", "text/html"}]
           }}

        {:get, "https://example.com/next"} ->
          {:ok,
           %{
             status: 200,
             body:
               ~s(<html><head><title>Next Page</title></head><body><p>Expanded browser content</p></body></html>),
             headers: [{"content-type", "text/html"}]
           }}
      end
    end

    assert {:ok, fetched} =
             BrowserAutomation.execute(
               %{action: "fetch_page", url: "https://example.com/start"},
               %{request_fn: request_fn}
             )

    assert fetched.title == "Start Page"
    assert Enum.any?(fetched.links, &(&1.text == "Read more"))

    assert {:ok, clicked} =
             BrowserAutomation.execute(
               %{action: "click_link", url: "https://example.com/start", link_text: "Read more"},
               %{request_fn: request_fn}
             )

    assert clicked.title == "Next Page"
    assert clicked.followed_href == "/next"
    assert clicked.forms == []
  end

  test "browser automation inspects forms, submits by parsed action, and writes snapshots" do
    request_fn = fn opts ->
      case {opts[:method], opts[:url]} do
        {:get, "https://example.com/form"} ->
          {:ok,
           %{
             status: 200,
             body:
               ~s(<html><head><title>Form Page</title></head><body><h1>Hydra Docs</h1><h2>Search</h2><form method="post" action="/submit"><input type="text" name="query" value="hydra" /><input type="hidden" name="scope" value="docs" /></form><table><tr><th>Name</th><th>Status</th></tr><tr><td>Hydra</td><td>Ready</td></tr></table></body></html>),
             headers: [{"content-type", "text/html"}]
           }}

        {:post, "https://example.com/submit"} ->
          assert opts[:form] == %{"query" => "hydra x", "scope" => "docs"}

          {:ok,
           %{
             status: 200,
             body: ~s(<html><body><p>Submitted hydra x</p></body></html>),
             headers: [{"content-type", "text/html"}]
           }}
      end
    end

    assert {:ok, forms} =
             BrowserAutomation.execute(
               %{action: "inspect_forms", url: "https://example.com/form"},
               %{request_fn: request_fn}
             )

    assert [%{action: "/submit", fields: [%{name: "query"}, %{name: "scope"}]}] = forms.forms

    assert {:ok, submitted} =
             BrowserAutomation.execute(
               %{
                 action: "submit_form",
                 url: "https://example.com/form",
                 form_index: 0,
                 fields: %{"query" => "hydra x"}
               },
               %{request_fn: request_fn}
             )

    assert submitted.url == "https://example.com/submit"

    assert {:ok, preview} =
             BrowserAutomation.execute(
               %{
                 action: "preview_form_submission",
                 url: "https://example.com/form",
                 form_index: 0,
                 fields: %{"query" => "hydra x"}
               },
               %{request_fn: request_fn}
             )

    assert preview.url == "https://example.com/submit"
    assert preview.fields == %{"query" => "hydra x", "scope" => "docs"}

    assert {:ok, headings} =
             BrowserAutomation.execute(
               %{action: "inspect_headings", url: "https://example.com/form"},
               %{request_fn: request_fn}
             )

    assert [%{level: 1, text: "Hydra Docs"}, %{level: 2, text: "Search"}] = headings.headings

    assert {:ok, tables} =
             BrowserAutomation.execute(
               %{action: "extract_tables", url: "https://example.com/form"},
               %{request_fn: request_fn}
             )

    assert [%{headers: ["Name", "Status"], rows: [["Hydra", "Ready"]]}] = tables.tables
    assert submitted.form_index == 0
    assert submitted.method == "POST"

    assert {:ok, snapshot} =
             BrowserAutomation.execute(
               %{action: "capture_snapshot", url: "https://example.com/form"},
               %{request_fn: request_fn}
             )

    assert snapshot.content_type == "image/svg+xml"
    assert File.exists?(snapshot.snapshot_path)
    assert File.read!(snapshot.snapshot_path) =~ "<svg"
  end

  test "browser automation blocks localhost targets before issuing a request" do
    request_fn = fn _opts ->
      send(self(), :browser_request_attempted)
      {:ok, %{status: 200, body: "should not happen", headers: []}}
    end

    assert {:error, :blocked_host} =
             BrowserAutomation.execute(
               %{action: "fetch_page", url: "http://localhost:4000/secret"},
               %{request_fn: request_fn}
             )

    refute_received :browser_request_attempted
  end

  test "shell commands run inside the workspace when allowlisted" do
    agent = create_agent()

    assert {:ok, result} =
             ShellCommand.execute(%{command: "pwd"}, %{workspace_root: agent.workspace_root})

    assert result.command == "pwd"
    assert result.output =~ agent.workspace_root
  end

  test "shell commands block disallowed git subcommands" do
    agent = create_agent()

    assert {:error, :git_subcommand_not_allowed} =
             ShellCommand.execute(
               %{command: "git checkout -b nope"},
               %{workspace_root: agent.workspace_root}
             )
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Tool Agent #{unique}",
        slug: "tool-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-tools-#{unique}"),
        description: "tool test agent",
        is_default: false
      })

    agent
  end
end
