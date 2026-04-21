defmodule HydraX.Product.SimulationBridge do
  @moduledoc """
  Connects the HydraX.Simulation engine to the product graph. Configures
  simulation runs from product graph data and feeds results back as synthetic signals.
  """

  import Ecto.Query
  require Logger

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
  # Autonomous simulation proposals
  # -------------------------------------------------------------------

  @doc """
  Create a simulation proposal from an agent. The simulation is created with
  status "proposed" and awaits approval (unless trust_level is "autonomous").
  """
  def propose_simulation(project_id, persona, attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)
    design_node_ids = Map.get(attrs, "design_node_ids", [])
    population_size = Map.get(attrs, "population_size", 100)

    # Validate design node IDs exist
    if design_node_ids != [] do
      existing = Product.list_design_nodes(project_id)
      existing_ids = MapSet.new(existing, & &1.id)
      invalid = Enum.reject(design_node_ids, &MapSet.member?(existing_ids, &1))

      if invalid != [] do
        {:error, {:invalid_design_nodes, invalid}}
      else
        do_propose(project_id, persona, attrs, design_node_ids, population_size)
      end
    else
      do_propose(project_id, persona, attrs, design_node_ids, population_size)
    end
  end

  defp do_propose(project_id, persona, attrs, design_node_ids, population_size) do
    alias HydraX.Product.PubSub, as: ProductPubSub

    sim_node =
      %SimulationNode{}
      |> SimulationNode.changeset(%{
        "project_id" => project_id,
        "status" => "proposed",
        "metadata" => %{
          "title" => Map.get(attrs, "title", "Untitled simulation"),
          "rationale" => Map.get(attrs, "rationale"),
          "proposed_by" => persona,
          "design_node_ids" => design_node_ids,
          "population_size" => population_size,
          "comparison_mode" => Map.get(attrs, "comparison_mode", false)
        }
      })
      |> Repo.insert!()

    # Check trust level for auto-start
    project = Product.get_project!(project_id)

    if project.trust_level == "autonomous" do
      run_from_proposal(project_id, sim_node.id)
    else
      # Emit stream event for approval
      ProductPubSub.broadcast_project_event(
        project_id,
        "simulation.proposed",
        %{
          sim_node_id: sim_node.id,
          title: (sim_node.metadata || %{})["title"],
          rationale: (sim_node.metadata || %{})["rationale"],
          proposed_by: persona
        }
      )
    end

    {:ok, sim_node}
  end

  @doc """
  Run a previously proposed simulation. Guards against double-execution
  by checking that the simulation is still in "proposed" status.
  Uses Task.Supervisor for fault-tolerant async execution.
  """
  def run_from_proposal(project_id, sim_node_id) do
    alias HydraX.Product.PubSub, as: ProductPubSub

    # Atomic status transition: only update if still "proposed" (prevents double-approval race)
    now = DateTime.utc_now()

    {count, _} =
      SimulationNode
      |> where([s], s.id == ^sim_node_id and s.status == "proposed")
      |> Repo.update_all(set: [status: "running", updated_at: now])

    if count == 0 do
      {:error, :not_in_proposed_status}
    else
      sim_node = Repo.get!(SimulationNode, sim_node_id)
      metadata = sim_node.metadata || %{}
      design_node_ids = Map.get(metadata, "design_node_ids", [])
      _population = Map.get(metadata, "population_size", 100)

      {:ok, scenario} = build_scenario_from_design(project_id, design_node_ids)
      {:ok, archetypes} = build_archetypes_from_insights(project_id)

      # Run async with supervision (not bare Task.start which is fire-and-forget)
      Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
        try do
          # Placeholder for actual simulation execution
          results = %{
            scenario: scenario,
            archetypes: archetypes,
            status: "completed",
            completed_at: DateTime.utc_now()
          }

          sim_node
          |> SimulationNode.changeset(%{
            "status" => "completed",
            "metadata" => Map.merge(metadata, %{"results" => results})
          })
          |> Repo.update!()

          ProductPubSub.broadcast_project_event(
            project_id,
            "simulation.completed",
            %{sim_node_id: sim_node_id, title: metadata["title"]}
          )
        rescue
          error ->
            Logger.error("[SimulationBridge] Simulation #{sim_node_id} failed: #{inspect(error)}")

            sim_node
            |> SimulationNode.changeset(%{
              "status" => "failed",
              "metadata" => Map.merge(metadata, %{"error" => inspect(error)})
            })
            |> Repo.update!()

            ProductPubSub.broadcast_project_event(
              project_id,
              "simulation.failed",
              %{sim_node_id: sim_node_id, title: metadata["title"], error: inspect(error)}
            )
        end
      end)

      {:ok, sim_node}
    end
  end

  # -------------------------------------------------------------------
  # Results integration
  # -------------------------------------------------------------------

  def import_simulation_results(_project_id, simulation_node_id) do
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
