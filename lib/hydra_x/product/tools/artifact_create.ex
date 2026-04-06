defmodule HydraX.Product.Tools.ArtifactCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "artifact_create"

  @impl true
  def description,
    do: "Create a new living artifact — a document maintained over time (competitive analysis, strategy memo, etc.)"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "artifact_create",
      description:
        "Create a new living artifact. Use for documents that should be maintained over time " <>
        "(competitive analysis, strategy memo, design language, etc.). The artifact will be " <>
        "versioned automatically on future updates.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Title for the artifact"},
          artifact_type: %{
            type: "string",
            enum: ["competitive_analysis", "strategy_memo", "project_summary", "decision_log", "design_language", "custom"],
            description: "Type of artifact"
          },
          body: %{type: "string", description: "Initial content in markdown"}
        },
        required: ["title", "artifact_type", "body"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         persona = params["product_persona"] || "system",
         attrs = %{
           "title" => params["title"],
           "artifact_type" => params["artifact_type"],
           "body" => params["body"],
           "owner_persona" => persona,
           "last_updated_by" => persona
         },
         {:ok, artifact} <- Product.create_artifact(project_id, attrs) do
      {:ok, %{artifact: %{id: artifact.id, title: artifact.title, type: artifact.artifact_type}}}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def result_summary(%{artifact: artifact}), do: "created artifact #{artifact.id}: #{artifact.title}"
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
