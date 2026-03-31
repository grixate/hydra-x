defmodule HydraX.Product.Tools.InsightCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product
  alias HydraX.Product.BoardAwareTools

  @impl true
  def name, do: "insight_create"

  @impl true
  def description, do: "Create a grounded product insight backed by source evidence"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "insight_create",
      description:
        "Create a product insight from grounded evidence. Always provide source chunk ids that support the claim.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Short title for the insight"},
          body: %{type: "string", description: "Insight statement or synthesis"},
          evidence_chunk_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Source chunk ids supporting the insight"
          },
          status: %{type: "string", description: "Insight status, usually draft or accepted"}
        },
        required: ["title", "body", "evidence_chunk_ids"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    if session_id = BoardAwareTools.board_session_id(params) do
      BoardAwareTools.create_board_node(session_id, "insight", params)
    else
      execute_graph(params)
    end
  end

  defp execute_graph(params) do
    with {:ok, project_id} <- project_id(params),
         {:ok, insight} <- Product.create_insight(project_id, params) do
      {:ok,
       %{
         insight: %{
           id: insight.id,
           title: insight.title,
           status: insight.status,
           evidence_count: length(insight.insight_evidence || [])
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
  def result_summary(%{insight: insight}), do: "created insight #{insight.id}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end

      _ ->
        {:error, :product_project_context_required}
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
