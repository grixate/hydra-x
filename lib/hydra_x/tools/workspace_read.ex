defmodule HydraX.Tools.WorkspaceRead do
  @behaviour HydraX.Tool

  alias HydraX.Safety.PathGuard

  @max_excerpt 4_000

  @impl true
  def name, do: "workspace_read"

  @impl true
  def description, do: "Read a file from the agent workspace without leaving the workspace root"

  @impl true
  def tool_schema do
    %{
      name: "workspace_read",
      description: "Read the contents of a file from the agent workspace. Use this when the user asks to read, show, or open a file.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "Relative path within the workspace (e.g. \"SOUL.md\", \"memory/MEMORY.md\")"}
        },
        required: ["path"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with workspace_root when is_binary(workspace_root) <- context[:workspace_root],
         path when is_binary(path) <- params[:path] || params["path"],
         {:ok, resolved_path} <- PathGuard.resolve_workspace_path(workspace_root, path),
         true <- File.regular?(resolved_path) or {:error, :not_found},
         {:ok, content} <- File.read(resolved_path) do
      excerpt = String.slice(content, 0, @max_excerpt)

      {:ok,
       %{
         path: path,
         resolved_path: resolved_path,
         excerpt: excerpt,
         truncated: String.length(content) > @max_excerpt
       }}
    else
      nil -> {:error, :missing_workspace_root}
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
