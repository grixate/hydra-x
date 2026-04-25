defmodule HydraX.Product.Tools.CodeSearch do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @max_results 100

  @impl true
  def name, do: "code_search"

  @impl true
  def description,
    do: "Search the project workspace for a regex pattern using ripgrep-compatible syntax."

  @impl true
  def safety_classification, do: "workspace_read"

  @impl true
  def tool_schema do
    %{
      name: "code_search",
      description:
        "Search file contents in the project workspace for a regular expression. Returns up to 100 matches with line numbers.",
      input_schema: %{
        type: "object",
        properties: %{
          pattern: %{type: "string", description: "Regular expression to search for."},
          path: %{
            type: "string",
            description: "Optional sub-path to limit the search. Defaults to workspace root."
          },
          glob: %{type: "string", description: "Optional file glob filter, e.g. \"*.ts\"."}
        },
        required: ["pattern"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    pattern = params[:pattern] || params["pattern"]
    sub_path = params[:path] || params["path"] || "."
    glob = params[:glob] || params["glob"]

    cond do
      not is_binary(pattern) or pattern == "" ->
        {:error, :missing_pattern}

      true ->
        CodeWorkspaceHelpers.with_workspace(context, fn backend, workspace ->
          args = build_rg_args(pattern, sub_path, glob)

          case backend.exec(workspace, args, timeout_ms: 30_000) do
            {:ok, %{exit_code: 0, stdout: out}} ->
              {:ok, %{pattern: pattern, matches: parse_matches(out)}}

            {:ok, %{exit_code: 1}} ->
              {:ok, %{pattern: pattern, matches: []}}

            {:ok, %{exit_code: code, stdout: out}} ->
              {:error, {:rg_error, code, String.slice(out, 0, 500)}}

            {:error, reason} ->
              {:error, reason}
          end
        end)
    end
  end

  defp build_rg_args(pattern, sub_path, glob) do
    base = [
      "rg",
      "--line-number",
      "--no-heading",
      "--max-count",
      Integer.to_string(@max_results),
      pattern
    ]

    base = if glob, do: base ++ ["--glob", glob], else: base
    base ++ [sub_path]
  end

  defp parse_matches(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.take(@max_results)
    |> Enum.map(fn line ->
      case String.split(line, ":", parts: 3) do
        [file, lineno, text] -> %{file: file, line: lineno, text: text}
        _ -> %{raw: line}
      end
    end)
  end

  @impl true
  def result_summary(%{pattern: pat, matches: matches}),
    do: "search #{inspect(pat)} → #{length(matches)} matches"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
