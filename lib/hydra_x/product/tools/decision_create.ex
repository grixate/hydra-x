defmodule HydraX.Product.Tools.DecisionCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product
  alias HydraX.Product.BoardAwareTools
  alias HydraX.Product.Graph

  @impl true
  def name, do: "decision_create"

  @impl true
  def description,
    do:
      "Record a product decision with reasoning and evidence links. Decisions are permanent records of choices made. They constrain downstream work."

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "decision_create",
      description:
        "Record a product decision with reasoning and evidence links. Always include alternatives_considered and reasoning. Decisions constrain downstream work — treat them accordingly.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "What was decided"},
          body: %{type: "string", description: "Full reasoning for the decision"},
          alternatives_considered: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                title: %{type: "string"},
                description: %{type: "string"},
                rejected_reason: %{type: "string"}
              }
            },
            description: "Alternatives that were considered and why they were rejected"
          },
          insight_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Insight IDs that informed this decision"
          },
          status: %{
            type: "string",
            enum: ["active", "draft"],
            description: "Decision status (default: active)"
          }
        },
        required: ["title", "body"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    if session_id = BoardAwareTools.board_session_id(params) do
      BoardAwareTools.create_board_node(session_id, "decision", params)
    else
      execute_graph(params)
    end
  end

  defp execute_graph(params) do
    with {:ok, project_id} <- extract_project_id(params) do
      attrs = %{
        "title" => params[:title] || params["title"],
        "body" => params[:body] || params["body"],
        "status" => params[:status] || params["status"] || "active",
        "alternatives_considered" => params[:alternatives_considered] || params["alternatives_considered"] || [],
        "decided_by" => "agent",
        "decided_at" => DateTime.utc_now()
      }

      case Product.create_decision(project_id, attrs) do
        {:ok, decision} ->
          link_insights(project_id, decision.id, params)

          {:ok,
           %{
             decision: %{
               id: decision.id,
               title: decision.title,
               status: decision.status
             }
           }}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def result_summary(%{decision: d}), do: "recorded decision #{d.id}: #{d.title}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp link_insights(project_id, decision_id, params) do
    insight_ids = params[:insight_ids] || params["insight_ids"] || []

    Enum.each(insight_ids, fn insight_id ->
      Graph.link_nodes(project_id, "insight", insight_id, "decision", decision_id, "lineage")
    end)
  end

  defp extract_project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) -> {:ok, value}

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
