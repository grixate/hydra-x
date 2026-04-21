defmodule HydraX.Product.Tools.CodeRead do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @max_excerpt 8_000

  @impl true
  def name, do: "code_read"

  @impl true
  def description,
    do: "Read a file from the project workspace (the per-project sandbox)."

  @impl true
  def safety_classification, do: "workspace_read"

  @impl true
  def tool_schema do
    %{
      name: "code_read",
      description:
        "Read the contents of a file from the project workspace. The path is relative to the workspace root.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path within the project workspace, e.g. \"src/main.ts\"."
          }
        },
        required: ["path"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with {:ok, path} <- CodeWorkspaceHelpers.fetch_path(params) do
      CodeWorkspaceHelpers.with_workspace(context, fn backend, workspace ->
        case backend.read_file(workspace, path) do
          {:ok, content} ->
            excerpt = String.slice(content, 0, @max_excerpt)

            {:ok,
             %{
               path: path,
               excerpt: excerpt,
               truncated: byte_size(excerpt) < byte_size(content),
               size: byte_size(content)
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  @impl true
  def result_summary(%{path: path, size: size}), do: "read #{path} (#{size}b)"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
