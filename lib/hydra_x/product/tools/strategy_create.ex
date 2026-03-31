defmodule HydraX.Product.Tools.StrategyCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product
  alias HydraX.Product.BoardAwareTools
  alias HydraX.Product.Graph

  @impl true
  def name, do: "strategy_create"

  @impl true
  def description,
    do:
      "Define a strategic direction that groups related decisions. A strategy is a coherent cluster of decisions pointing in the same direction."

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "strategy_create",
      description:
        "Define a strategic direction that groups related decisions. A strategy is a coherent cluster of decisions pointing in the same direction.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Strategy title"},
          body: %{type: "string", description: "Description of the strategic direction"},
          decision_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Decision IDs that compose this strategy"
          },
          status: %{
            type: "string",
            enum: ["active", "draft"],
            description: "Strategy status (default: active)"
          }
        },
        required: ["title", "body"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    if session_id = BoardAwareTools.board_session_id(params) do
      BoardAwareTools.create_board_node(session_id, "strategy", params)
    else
      execute_graph(params)
    end
  end

  defp execute_graph(params) do
    with {:ok, project_id} <- extract_project_id(params) do
      attrs = %{
        "title" => params[:title] || params["title"],
        "body" => params[:body] || params["body"],
        "status" => params[:status] || params["status"] || "active"
      }

      case Product.create_strategy(project_id, attrs) do
        {:ok, strategy} ->
          link_decisions(project_id, strategy.id, params)

          {:ok,
           %{
             strategy: %{
               id: strategy.id,
               title: strategy.title,
               status: strategy.status
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
  def result_summary(%{strategy: s}), do: "created strategy #{s.id}: #{s.title}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp link_decisions(project_id, strategy_id, params) do
    decision_ids = params[:decision_ids] || params["decision_ids"] || []

    Enum.each(decision_ids, fn decision_id ->
      Graph.link_nodes(project_id, "decision", decision_id, "strategy", strategy_id, "lineage")
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
