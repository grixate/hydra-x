defmodule HydraX.Product.Tools.DesignUpdate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "design_update"

  @impl true
  def description, do: "Update an existing design node"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "design_update",
      description: "Update an existing design node's title, body, node_type, or status.",
      input_schema: %{
        type: "object",
        properties: %{
          id: %{type: "integer", description: "Design node ID to update"},
          title: %{type: "string", description: "Updated title"},
          body: %{type: "string", description: "Updated description"},
          node_type: %{
            type: "string",
            enum: ["user_flow", "wireframe", "interaction_pattern", "component_spec", "design_rationale"]
          },
          status: %{type: "string", enum: ["draft", "active", "superseded", "archived"]}
        },
        required: ["id"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    id = params[:id] || params["id"]
    node = Product.get_design_node!(id)

    case Product.update_design_node(node, params) do
      {:ok, updated} ->
        {:ok, %{design_node: %{id: updated.id, title: updated.title, status: updated.status}}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def result_summary(%{design_node: node}), do: "updated design node #{node.id}"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
