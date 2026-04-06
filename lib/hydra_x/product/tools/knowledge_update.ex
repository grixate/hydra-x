defmodule HydraX.Product.Tools.KnowledgeUpdate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "knowledge_update"

  @impl true
  def description,
    do: "Propose an update to an existing knowledge entry with new information"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "knowledge_update",
      description:
        "Propose an update to an existing knowledge entry. Use when you discover new " <>
        "information that should be added, or when existing guidance is outdated. " <>
        "The update will be reviewed before applying.",
      input_schema: %{
        type: "object",
        properties: %{
          knowledge_entry_id: %{type: "integer", description: "ID of the entry to update"},
          updated_content: %{type: "string", description: "The full updated content"},
          change_reason: %{type: "string", description: "Why this update is needed"}
        },
        required: ["knowledge_entry_id", "updated_content", "change_reason"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         entry_id = params["knowledge_entry_id"],
         {:ok, entry} <- fetch_knowledge_entry(entry_id, project_id),
         attrs = %{
           "content" => params["updated_content"],
           "metadata" =>
             Map.merge(entry.metadata || %{}, %{
               "pending_update" => true,
               "change_reason" => params["change_reason"],
               "previous_content" => entry.content
             }),
           "status" => "pending_review"
         },
         {:ok, updated} <- Product.update_knowledge_entry(entry, attrs) do
      {:ok,
       %{
         knowledge_entry: %{
           id: updated.id,
           title: updated.title,
           status: updated.status
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
  def result_summary(%{knowledge_entry: entry}),
    do: "proposed update to knowledge entry #{entry.id}: #{entry.title}"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp fetch_knowledge_entry(entry_id, project_id) do
    try do
      entry = Product.get_knowledge_entry!(entry_id)

      if entry.project_id == project_id do
        {:ok, entry}
      else
        {:error, :not_found}
      end
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

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
