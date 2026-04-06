defmodule HydraX.Product.Tools.ArtifactUpdate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "artifact_update"

  @impl true
  def description,
    do: "Update a living artifact with new content. Previous version is preserved in history."

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "artifact_update",
      description:
        "Update a living artifact with new content. The artifact retains its identity. " <>
        "Previous version is preserved in history. Always provide the complete updated body.",
      input_schema: %{
        type: "object",
        properties: %{
          artifact_id: %{type: "integer", description: "The artifact to update"},
          new_body: %{type: "string", description: "The complete updated content (markdown)"},
          change_summary: %{
            type: "string",
            description: "Brief description of what changed and why"
          }
        },
        required: ["artifact_id", "new_body", "change_summary"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         persona = params["product_persona"] || "system",
         attrs = %{
           "body" => params["new_body"],
           "last_updated_by" => persona,
           "change_summary" => params["change_summary"]
         },
         {:ok, artifact} <- Product.update_artifact(project_id, params["artifact_id"], attrs) do
      {:ok,
       %{
         artifact: %{
           id: artifact.id,
           title: artifact.title,
           version: artifact.version,
           change_summary: params["change_summary"]
         }
       }}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def result_summary(%{artifact: artifact}),
    do: "updated artifact #{artifact.id} to v#{artifact.version}"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end
      _ -> {:error, :product_project_context_required}
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
