defmodule HydraX.Tools.WorkspaceWrite do
  @behaviour HydraX.Tool

  alias HydraX.Safety.PathGuard

  @impl true
  def name, do: "workspace_write"

  @impl true
  def description, do: "Write a file inside the agent workspace"

  @impl true
  def safety_classification, do: "workspace_write"

  @impl true
  def tool_schema do
    %{
      name: "workspace_write",
      description:
        "Write or append content to a file inside the agent workspace. Use this when the user explicitly asks to create or update a workspace file.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path within the workspace to write."
          },
          content: %{
            type: "string",
            description: "File content to write."
          },
          append: %{
            type: "boolean",
            description: "If true, append to the file instead of replacing it."
          }
        },
        required: ["path", "content"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with workspace_root when is_binary(workspace_root) <- context[:workspace_root],
         path when is_binary(path) <- params[:path] || params["path"],
         content when is_binary(content) <- params[:content] || params["content"],
         append? <- truthy?(params[:append] || params["append"]),
         {:ok, resolved_path} <- PathGuard.resolve_workspace_path(workspace_root, path),
         :ok <- ensure_parent_dir(resolved_path),
         :ok <- write_file(resolved_path, content, append?) do
      {:ok,
       %{
         path: path,
         resolved_path: resolved_path,
         bytes_written: byte_size(content),
         append: append?
       }}
    else
      nil -> {:error, :missing_workspace_root}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_content}
    end
  end

  @impl true
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(%{"error" => error}) when is_binary(error), do: error
  def result_summary(%{path: path, append: true}), do: "appended #{path}"
  def result_summary(%{path: path}), do: "wrote #{path}"
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp write_file(path, content, true), do: File.write(path, content, [:append])
  defp write_file(path, content, false), do: File.write(path, content)

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
