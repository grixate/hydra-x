defmodule HydraX.Product.Tools.DesignCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product
  alias HydraX.Product.BoardAwareTools
  alias HydraX.Product.Graph

  @impl true
  def name, do: "design_create"

  @impl true
  def description, do: "Create a design node linked to requirements and insights"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "design_create",
      description:
        "Create a UX design artifact (user flow, wireframe, interaction pattern, component spec, or design rationale). Link to the requirements and insights it addresses.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Short title for the design node"},
          body: %{type: "string", description: "Detailed design description or specification"},
          node_type: %{
            type: "string",
            enum: ["user_flow", "wireframe", "interaction_pattern", "component_spec", "design_rationale"],
            description: "Type of design artifact"
          },
          linked_requirement_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Requirement IDs this design addresses"
          },
          linked_insight_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Insight IDs informing this design"
          },
          reasoning: %{type: "string", description: "Why this design choice was made"}
        },
        required: ["title", "body", "node_type"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    if session_id = BoardAwareTools.board_session_id(params) do
      BoardAwareTools.create_board_node(session_id, "design_node", params)
    else
      execute_graph(params)
    end
  end

  defp execute_graph(params) do
    with {:ok, project_id} <- extract_project_id(params),
         {:ok, node} <- Product.create_design_node(project_id, params) do
      link_requirements(project_id, node.id, params)
      link_insights(project_id, node.id, params)

      {:ok,
       %{
         design_node: %{
           id: node.id,
           title: node.title,
           node_type: node.node_type,
           status: node.status
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
  def result_summary(%{design_node: node}), do: "created design node #{node.id}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp link_requirements(project_id, node_id, params) do
    req_ids = params[:linked_requirement_ids] || params["linked_requirement_ids"] || []

    Enum.each(req_ids, fn req_id ->
      Graph.link_nodes(project_id, "requirement", req_id, "design_node", node_id, "lineage")
    end)
  end

  defp link_insights(project_id, node_id, params) do
    insight_ids = params[:linked_insight_ids] || params["linked_insight_ids"] || []

    Enum.each(insight_ids, fn insight_id ->
      Graph.link_nodes(project_id, "insight", insight_id, "design_node", node_id, "supports")
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
