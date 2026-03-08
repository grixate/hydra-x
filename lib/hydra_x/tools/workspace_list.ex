defmodule HydraX.Tools.WorkspaceList do
  @behaviour HydraX.Tool

  alias HydraX.Safety.PathGuard

  @max_entries 200

  @impl true
  def name, do: "workspace_list"

  @impl true
  def description, do: "List files and directories inside the agent workspace"

  @impl true
  def tool_schema do
    %{
      name: "workspace_list",
      description:
        "List files and directories from the agent workspace. Use this when the user asks what files exist or what is inside a workspace folder.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description:
              "Optional relative path within the workspace. Defaults to the workspace root."
          }
        }
      }
    }
  end

  @impl true
  def execute(params, context) do
    with workspace_root when is_binary(workspace_root) <- context[:workspace_root],
         {:ok, relative_path, resolved_path} <-
           resolve_target(workspace_root, params[:path] || params["path"]),
         true <- File.dir?(resolved_path) or {:error, :not_found},
         {:ok, entries} <- File.ls(resolved_path) do
      listed_entries =
        entries
        |> Enum.sort()
        |> Enum.take(@max_entries)
        |> Enum.map(fn entry ->
          child_path = Path.join(resolved_path, entry)

          %{
            name: entry,
            path: normalize_child_path(relative_path, entry),
            type: entry_type(child_path)
          }
        end)

      {:ok,
       %{
         path: relative_path,
         resolved_path: resolved_path,
         entries: listed_entries,
         truncated: length(entries) > @max_entries
       }}
    else
      nil -> {:error, :missing_workspace_root}
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_target(workspace_root, nil), do: {:ok, ".", Path.expand(workspace_root)}
  defp resolve_target(workspace_root, ""), do: {:ok, ".", Path.expand(workspace_root)}
  defp resolve_target(workspace_root, "."), do: {:ok, ".", Path.expand(workspace_root)}

  defp resolve_target(workspace_root, path) do
    case PathGuard.resolve_workspace_path(workspace_root, path) do
      {:ok, resolved_path} -> {:ok, path, resolved_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp entry_type(path) do
    cond do
      File.dir?(path) -> "directory"
      File.regular?(path) -> "file"
      true -> "other"
    end
  end

  defp normalize_child_path(".", entry), do: entry
  defp normalize_child_path(path, entry), do: Path.join(path, entry)
end
