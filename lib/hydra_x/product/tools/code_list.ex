defmodule HydraX.Product.Tools.CodeList do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @impl true
  def name, do: "code_list"

  @impl true
  def description, do: "List directory entries in the project workspace."

  @impl true
  def safety_classification, do: "workspace_read"

  @impl true
  def tool_schema do
    %{
      name: "code_list",
      description:
        "List files and directories at a given relative path in the project workspace. Pass an empty string for the root.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative directory path within the workspace. Use \"\" or \".\" for root."
          }
        },
        required: ["path"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    path =
      case params[:path] || params["path"] do
        nil -> "."
        "" -> "."
        s when is_binary(s) -> s
      end

    CodeWorkspaceHelpers.with_workspace(context, fn backend, workspace ->
      case backend.list_dir(workspace, path) do
        {:ok, entries} -> {:ok, %{path: path, entries: entries}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @impl true
  def result_summary(%{path: path, entries: entries}),
    do: "listed #{path} (#{length(entries)} entries)"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
