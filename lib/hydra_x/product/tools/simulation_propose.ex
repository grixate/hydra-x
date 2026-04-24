defmodule HydraX.Product.Tools.SimulationPropose do
  @behaviour HydraX.Tool

  alias HydraX.Product.SimulationBridge

  @impl true
  def name, do: "simulation_propose"

  @impl true
  def description,
    do: "Propose a simulation to resolve uncertainty in a decision or design choice"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "simulation_propose",
      description:
        "Propose a simulation to resolve uncertainty in a decision or design choice. " <>
          "Specify what to test, which design nodes or requirements to use as scenarios, " <>
          "and why this simulation would help. The simulation will run asynchronously.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Name for this simulation"},
          rationale: %{
            type: "string",
            description: "Why this simulation is needed and what question it answers"
          },
          design_node_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "Design nodes that define the scenarios to test"
          },
          population_size: %{
            type: "integer",
            description: "Number of simulated users (50, 100, 200). Default 100."
          },
          comparison_mode: %{
            type: "boolean",
            description: "If true, run A/B comparison between design alternatives"
          }
        },
        required: ["title", "rationale"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         persona = params["product_persona"] || "strategist",
         {:ok, sim_node} <- SimulationBridge.propose_simulation(project_id, persona, params) do
      {:ok,
       %{
         simulation: %{
           id: sim_node.id,
           status: sim_node.status,
           title: params["title"]
         }
       }}
    else
      {:error, {:invalid_design_nodes, ids}} ->
        {:error, %{error: "invalid_design_nodes", ids: ids}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def result_summary(%{simulation: sim}),
    do: "proposed simulation #{sim.id}: #{sim.title} (#{sim.status})"

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
end
