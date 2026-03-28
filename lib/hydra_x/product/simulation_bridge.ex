defmodule HydraX.Product.SimulationBridge do
  @moduledoc """
  Connects the HydraX.Simulation engine to the product graph. Configures
  simulation runs from product graph data and feeds results back as synthetic signals.
  """

  import Ecto.Query

  alias HydraX.Product
  alias HydraX.Product.Graph
  alias HydraX.Product.Insight
  alias HydraX.Product.SimulationNode
  alias HydraX.Repo

  # -------------------------------------------------------------------
  # Configuration from graph
  # -------------------------------------------------------------------

  def build_archetypes_from_insights(project_id) do
    insights =
      Insight
      |> where([i], i.project_id == ^project_id and i.status in ["accepted", "draft"])
      |> Repo.all()

    archetypes =
      insights
      |> Enum.map(fn insight ->
        %{
          source_insight_id: insight.id,
          title: insight.title,
          description: String.slice(insight.body || "", 0, 500),
          traits: extract_traits_from_insight(insight)
        }
      end)

    {:ok, archetypes}
  end

  def build_scenario_from_design(project_id, design_node_ids) do
    design_nodes =
      Product.list_design_nodes(project_id)
      |> Enum.filter(fn d -> d.id in design_node_ids end)

    scenario = %{
      design_nodes: Enum.map(design_nodes, fn d ->
        %{id: d.id, title: d.title, type: d.node_type, body: d.body}
      end),
      requirements: linked_requirements(project_id, design_node_ids)
    }

    {:ok, scenario}
  end

  # -------------------------------------------------------------------
  # Run simulation
  # -------------------------------------------------------------------

  def run_product_simulation(project_id, opts \\ []) do
    archetypes = Keyword.get(opts, :archetypes)
    scenario = Keyword.get(opts, :scenario)

    archetypes = archetypes || elem(build_archetypes_from_insights(project_id), 1)

    sim_node =
      %SimulationNode{}
      |> SimulationNode.changeset(%{
        "project_id" => project_id,
        "status" => "configuring",
        "archetype_summary" => archetypes,
        "scenario_summary" => if(scenario, do: inspect(scenario, limit: 500), else: nil),
        "metadata" => Keyword.get(opts, :metadata, %{})
      })
      |> Repo.insert!()

    {:ok, sim_node}
  end

  # -------------------------------------------------------------------
  # Results integration
  # -------------------------------------------------------------------

  def import_simulation_results(project_id, simulation_node_id) do
    sim_node = Repo.get!(SimulationNode, simulation_node_id)

    if sim_node.results_imported do
      {:error, :already_imported}
    else
      # Mark as imported
      sim_node
      |> SimulationNode.changeset(%{"results_imported" => true, "status" => "completed"})
      |> Repo.update!()

      {:ok, %{simulation_node_id: sim_node.id, results_imported: true}}
    end
  end

  # -------------------------------------------------------------------
  # Query
  # -------------------------------------------------------------------

  def list_product_simulations(project_id) do
    SimulationNode
    |> where([s], s.project_id == ^project_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def get_product_simulation!(id) do
    Repo.get!(SimulationNode, id)
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp extract_traits_from_insight(insight) do
    # Simple trait extraction based on insight metadata
    metadata = insight.metadata || %{}
    %{
      type: Map.get(metadata, "insight_type", "general"),
      confidence: Map.get(metadata, "confidence", "medium")
    }
  end

  defp linked_requirements(project_id, design_node_ids) do
    edges =
      HydraX.Product.GraphEdge
      |> where(
        [e],
        e.project_id == ^project_id and
          e.to_node_type == "design_node" and
          e.to_node_id in ^design_node_ids and
          e.from_node_type == "requirement"
      )
      |> Repo.all()

    req_ids = Enum.map(edges, & &1.from_node_id) |> Enum.uniq()

    Graph.resolve_nodes(Enum.map(req_ids, fn id -> {"requirement", id} end))
    |> Enum.map(fn {_type, _id, record} ->
      %{id: record.id, title: record.title, body: record.body}
    end)
  end
end
