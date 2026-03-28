defmodule HydraX.Product.Tools.FeasibilityAssess do
  @behaviour HydraX.Tool

  import Ecto.Query

  alias HydraX.Product.ArchitectureNode
  alias HydraX.Product.Graph
  alias HydraX.Product.Insight
  alias HydraX.Product.Requirement
  alias HydraX.Product.RequirementInsight
  alias HydraX.Repo

  @impl true
  def name, do: "feasibility_assess"

  @impl true
  def description,
    do:
      "Evaluate the technical feasibility of a requirement. Loads requirement context, linked insights, and existing architecture nodes. This is a read-only assessment — use architecture_create after the operator approves the approach."

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "feasibility_assess",
      description:
        "Evaluate the technical feasibility of a requirement. Loads the requirement, its linked insights, and existing architecture context. This is a read-only assessment — use architecture_create after the operator approves the approach.",
      input_schema: %{
        type: "object",
        properties: %{
          requirement_id: %{type: "integer", description: "The requirement to assess"}
        },
        required: ["requirement_id"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params) do
      requirement_id = params[:requirement_id] || params["requirement_id"]

      case Repo.get(Requirement, requirement_id) do
        nil ->
          {:error, "requirement #{requirement_id} not found"}

        %{project_id: req_project_id} when req_project_id != project_id ->
          {:error, "requirement #{requirement_id} does not belong to this project"}

        requirement ->
          execute_assessment(project_id, requirement, requirement_id)
      end
    end
  end

  defp execute_assessment(project_id, requirement, requirement_id) do
      # Load linked insights
      linked_insights =
        RequirementInsight
        |> where([ri], ri.requirement_id == ^requirement_id)
        |> preload(:insight)
        |> Repo.all()
        |> Enum.map(fn ri ->
          %{
            id: ri.insight.id,
            title: ri.insight.title,
            body_excerpt: String.slice(ri.insight.body || "", 0, 300),
            status: ri.insight.status
          }
        end)

      # Load existing architecture nodes for context
      existing_arch =
        ArchitectureNode
        |> where([a], a.project_id == ^project_id and a.status == "active")
        |> order_by([a], desc: a.updated_at)
        |> limit(10)
        |> Repo.all()
        |> Enum.map(fn a ->
          %{
            id: a.id,
            title: a.title,
            node_type: a.node_type,
            body_excerpt: String.slice(a.body || "", 0, 200)
          }
        end)

      # Load upstream graph context
      upstream = Graph.trace_upstream(project_id, "requirement", requirement_id, max_depth: 3)

      {:ok,
       %{
         context: %{
           requirement: %{
             id: requirement.id,
             title: requirement.title,
             body: requirement.body,
             status: requirement.status
           },
           linked_insights: linked_insights,
           existing_architecture: existing_arch,
           upstream_chain:
             Enum.map(upstream, fn n ->
               %{node_type: n.node_type, node_id: n.node_id, edge_kind: n.edge_kind}
             end)
         }
       }}
  end

  @impl true
  def result_summary(%{context: c}),
    do:
      "loaded context for requirement #{c.requirement.id}: #{length(c.linked_insights)} insights, #{length(c.existing_architecture)} arch nodes"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

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
end
