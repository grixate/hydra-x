defmodule HydraX.Product.Tools.RequirementCreate do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "requirement_create"

  @impl true
  def description, do: "Create a product requirement linked to supporting insights"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "requirement_create",
      description:
        "Create a requirement linked to supporting insights. Ungrounded requirements cannot be accepted.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Short title for the requirement"},
          body: %{type: "string", description: "Requirement statement"},
          insight_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Supporting insight ids"
          },
          status: %{type: "string", description: "Requirement status, usually draft or accepted"}
        },
        required: ["title", "body"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         {:ok, requirement} <- Product.create_requirement(project_id, params) do
      {:ok,
       %{
         requirement: %{
           id: requirement.id,
           title: requirement.title,
           status: requirement.status,
           grounded: requirement.grounded,
           insight_count: length(requirement.requirement_insights || [])
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
  def result_summary(%{requirement: requirement}), do: "created requirement #{requirement.id}"
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
