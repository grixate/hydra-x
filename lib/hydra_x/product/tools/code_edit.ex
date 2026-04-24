defmodule HydraX.Product.Tools.CodeEdit do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @impl true
  def name, do: "code_edit"

  @impl true
  def description,
    do: "Apply an exact string replacement to a file in the project workspace."

  @impl true
  def safety_classification, do: "workspace_write"

  @impl true
  def tool_schema do
    %{
      name: "code_edit",
      description:
        "Replace `old_string` with `new_string` in a file. The `old_string` must match exactly and uniquely (or set `replace_all: true` to replace every occurrence).",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "Relative path within the project workspace."},
          old_string: %{
            type: "string",
            description: "Text to find. Must be unique unless replace_all is true."
          },
          new_string: %{type: "string", description: "Replacement text."},
          replace_all: %{
            type: "boolean",
            description: "Replace every occurrence (default false).",
            default: false
          }
        },
        required: ["path", "old_string", "new_string"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with {:ok, path} <- CodeWorkspaceHelpers.fetch_path(params),
         {:ok, old_str} <- fetch_string(params, :old_string),
         {:ok, new_str} <- fetch_string(params, :new_string) do
      replace_all = params[:replace_all] || params["replace_all"] || false

      CodeWorkspaceHelpers.with_workspace(context, fn backend, workspace ->
        with {:ok, content} <- backend.read_file(workspace, path),
             {:ok, updated, count} <- apply_edit(content, old_str, new_str, replace_all),
             :ok <- backend.write_file(workspace, path, updated) do
          {:ok, %{path: path, replacements: count}}
        end
      end)
    end
  end

  defp fetch_string(params, key) do
    str_key = Atom.to_string(key)

    case params[key] || params[str_key] do
      s when is_binary(s) and s != "" -> {:ok, s}
      _ -> {:error, {:missing, key}}
    end
  end

  defp apply_edit(content, old_str, new_str, replace_all) do
    case count_occurrences(content, old_str) do
      0 ->
        {:error, :old_string_not_found}

      n when n > 1 and not replace_all ->
        {:error, {:old_string_not_unique, n}}

      n ->
        {:ok, String.replace(content, old_str, new_str), n}
    end
  end

  defp count_occurrences(content, needle) do
    content
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  @impl true
  def result_summary(%{path: path, replacements: count}), do: "edited #{path} (#{count} repl)"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
