defmodule HydraX.Product.Tools.ArchitectureCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product
  alias HydraX.Product.Graph

  @impl true
  def name, do: "architecture_create"

  @impl true
  def description, do: "Create an architecture node linked to requirements"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "architecture_create",
      description:
        "Create a technical architecture decision or component spec. Link to the requirements it addresses.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Short title for the architecture node"},
          body: %{type: "string", description: "Detailed architecture description or specification"},
          node_type: %{
            type: "string",
            enum: ["system_design", "data_model", "api_contract", "infra_choice", "tech_selection"],
            description: "Type of architecture artifact"
          },
          requirement_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Requirement IDs this architecture serves"
          },
          decision_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Decision IDs that led to this architecture"
          }
        },
        required: ["title", "body", "node_type"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params),
         {:ok, node} <- Product.create_architecture_node(project_id, params) do
      link_requirements(project_id, node.id, params)
      link_decisions(project_id, node.id, params)

      {:ok,
       %{
         architecture_node: %{
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
  def result_summary(%{architecture_node: node}), do: "created architecture node #{node.id}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp link_requirements(project_id, node_id, params) do
    req_ids = params[:requirement_ids] || params["requirement_ids"] ||
              params[:linked_requirement_ids] || params["linked_requirement_ids"] || []

    Enum.each(req_ids, fn req_id ->
      Graph.link_nodes(project_id, "requirement", req_id, "architecture_node", node_id, "lineage")
    end)
  end

  defp link_decisions(project_id, node_id, params) do
    dec_ids = params[:decision_ids] || params["decision_ids"] || []

    Enum.each(dec_ids, fn dec_id ->
      Graph.link_nodes(project_id, "decision", dec_id, "architecture_node", node_id, "lineage")
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
