defmodule HydraX.Product.Tools.ArchitectureUpdate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "architecture_update"

  @impl true
  def description, do: "Update an existing architecture node"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "architecture_update",
      description: "Update an existing architecture node's title, body, node_type, or status.",
      input_schema: %{
        type: "object",
        properties: %{
          id: %{type: "integer", description: "Architecture node ID to update"},
          title: %{type: "string", description: "Updated title"},
          body: %{type: "string", description: "Updated description"},
          node_type: %{
            type: "string",
            enum: ["system_design", "data_model", "api_contract", "infra_choice", "tech_selection"]
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

    case HydraX.Repo.get(HydraX.Product.ArchitectureNode, id) do
      nil ->
        {:error, "architecture node #{id} not found"}

      node ->
        do_update(node, params)
    end
  end

  defp do_update(node, params) do
    case Product.update_architecture_node(node, params) do
      {:ok, updated} ->
        {:ok, %{architecture_node: %{id: updated.id, title: updated.title, status: updated.status}}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def result_summary(%{architecture_node: node}), do: "updated architecture node #{node.id}"
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
