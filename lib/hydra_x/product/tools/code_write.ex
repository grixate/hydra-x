defmodule HydraX.Product.Tools.CodeWrite do
  @behaviour HydraX.Tool

  alias HydraX.Product.Tools.CodeWorkspaceHelpers

  @impl true
  def name, do: "code_write"

  @impl true
  def description,
    do: "Create or overwrite a file in the project workspace."

  @impl true
  def safety_classification, do: "workspace_write"

  @impl true
  def tool_schema do
    %{
      name: "code_write",
      description:
        "Create or overwrite a file in the project workspace with the given content. Creates parent directories if needed.",
      input_schema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path within the project workspace."
          },
          content: %{
            type: "string",
            description: "Full file contents to write."
          }
        },
        required: ["path", "content"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    with {:ok, path} <- CodeWorkspaceHelpers.fetch_path(params),
         {:ok, content} <- fetch_content(params) do
      CodeWorkspaceHelpers.with_workspace(context, fn backend, workspace ->
        case backend.write_file(workspace, path, content) do
          :ok -> {:ok, %{path: path, bytes: byte_size(content)}}
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  defp fetch_content(params) do
    case params[:content] || params["content"] do
      content when is_binary(content) -> {:ok, content}
      _ -> {:error, :missing_content}
    end
  end

  @impl true
  def result_summary(%{path: path, bytes: bytes}), do: "wrote #{path} (#{bytes}b)"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
