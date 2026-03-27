defmodule HydraX.Product.Tools.InsightUpdate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "insight_update"

  @impl true
  def description, do: "Update an existing product insight and its evidence links"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "insight_update",
      description:
        "Update a product insight. Provide evidence chunk ids when the supporting evidence changes.",
      input_schema: %{
        type: "object",
        properties: %{
          insight_id: %{type: "integer", description: "Insight id to update"},
          title: %{type: "string", description: "Updated title"},
          body: %{type: "string", description: "Updated body"},
          status: %{type: "string", description: "Updated status"},
          evidence_chunk_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Replacement evidence chunk ids"
          }
        },
        required: ["insight_id"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         {:ok, insight_id} <- record_id(params, :insight_id),
         insight <- Product.get_project_insight!(project_id, insight_id),
         {:ok, updated} <- Product.update_insight(insight, params) do
      {:ok,
       %{
         insight: %{
           id: updated.id,
           title: updated.title,
           status: updated.status,
           evidence_count: length(updated.insight_evidence || [])
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
  def result_summary(%{insight: insight}), do: "updated insight #{insight.id}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp project_id(params), do: record_id(params, :project_id)

  defp record_id(params, key) do
    case params[key] || params[to_string(key)] do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :invalid_identifier}
        end

      _ ->
        {:error, :invalid_identifier}
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
