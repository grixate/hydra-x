defmodule HydraX.Tools.WorkspacePatch do
  @behaviour HydraX.Tool

  alias HydraX.Safety.PathGuard

  @impl true
  def name, do: "workspace_patch"

  @impl true
  def description, do: "Apply a precise search-and-replace patch inside the agent workspace"

  @impl true
  def safety_classification, do: "workspace_write"

  @impl true
  def tool_schema do
    %{
      name: "workspace_patch",
      description:
        "Apply a precise in-place text patch to a workspace file by replacing a matching string. Use this for targeted edits instead of rewriting the full file.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path within the workspace to patch."
          },
          search: %{
            type: "string",
            description: "Exact text to find in the file."
          },
          replace: %{
            type: "string",
            description: "Replacement text."
          },
          replace_all: %{
            type: "boolean",
            description: "If true, replace all matches. Otherwise replace the first match only."
          }
        },
        required: ["path", "search", "replace"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with workspace_root when is_binary(workspace_root) <- context[:workspace_root],
         path when is_binary(path) <- params[:path] || params["path"],
         search when is_binary(search) and search != "" <- params[:search] || params["search"],
         replace when is_binary(replace) <- params[:replace] || params["replace"],
         replace_all? <- truthy?(params[:replace_all] || params["replace_all"]),
         {:ok, resolved_path} <- PathGuard.resolve_workspace_path(workspace_root, path),
         {:ok, original} <- File.read(resolved_path),
         {:ok, updated, replacements} <- apply_patch(original, search, replace, replace_all?),
         :ok <- File.write(resolved_path, updated) do
      {:ok,
       %{
         path: path,
         resolved_path: resolved_path,
         replacements: replacements,
         replace_all: replace_all?,
         bytes_written: byte_size(updated)
       }}
    else
      nil -> {:error, :missing_workspace_root}
      false -> {:error, :invalid_patch}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_patch}
    end
  end

  @impl true
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error

  def result_summary(%{path: path, replacements: replacements}) do
    "patched #{path} (#{replacements} replacements)"
  end

  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp apply_patch(original, search, replace, true) do
    count = count_occurrences(original, search)

    if count > 0 do
      {:ok, String.replace(original, search, replace), count}
    else
      {:error, :search_not_found}
    end
  end

  defp apply_patch(original, search, replace, false) do
    if String.contains?(original, search) do
      {:ok, String.replace(original, search, replace, global: false), 1}
    else
      {:error, :search_not_found}
    end
  end

  defp count_occurrences(content, needle) do
    content
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
