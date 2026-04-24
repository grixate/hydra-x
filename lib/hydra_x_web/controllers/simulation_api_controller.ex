defmodule HydraXWeb.SimulationAPIController do
  use HydraXWeb, :controller

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Product
  alias HydraX.Product.SimulationBridge

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    simulations = SimulationBridge.list_product_simulations(project_id)
    json(conn, %{data: Enum.map(simulations, &simulation_json/1)})
  end

  def create(conn, %{"project_id" => project_id} = params) do
    simulation_params = params["simulation"] || %{}

    archetypes = simulation_params["archetypes"]
    scenario = simulation_params["scenario"]
    population_size = simulation_params["population_size"] || 200
    max_ticks = simulation_params["max_ticks"] || 50
    comparison_mode = simulation_params["comparison_mode"] || false
    scenario_b = simulation_params["scenario_b"]
    selected_node_ids = simulation_params["selected_node_ids"] || []
    title = simulation_params["title"]

    opts =
      [
        metadata: %{
          "title" => title,
          "population_size" => population_size,
          "max_ticks" => max_ticks,
          "comparison_mode" => comparison_mode,
          "scenario_b" => scenario_b,
          "selected_node_ids" => selected_node_ids
        }
      ]
      |> maybe_add(:archetypes, archetypes)
      |> maybe_add(:scenario, scenario)

    {:ok, sim_node} = SimulationBridge.run_product_simulation(project_id, opts)

    conn
    |> put_status(:created)
    |> json(%{data: simulation_json(sim_node)})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    sim_node = SimulationBridge.get_product_simulation!(id)

    if to_string(sim_node.project_id) == to_string(project_id) do
      json(conn, %{data: simulation_json(sim_node)})
    else
      conn |> put_status(:not_found) |> json(%{error: "Not found"})
    end
  end

  def archetypes(conn, %{"project_id" => project_id}) do
    {:ok, archetypes} = SimulationBridge.build_archetypes_from_insights(project_id)
    json(conn, %{data: archetypes})
  end

  def graph_nodes(conn, %{"project_id" => project_id}) do
    decisions = Product.list_decisions(project_id) |> Enum.map(&decision_node/1)
    requirements = Product.list_requirements(project_id) |> Enum.map(&requirement_node/1)
    design_nodes = Product.list_design_nodes(project_id) |> Enum.map(&design_node/1)

    json(conn, %{data: decisions ++ requirements ++ design_nodes})
  end

  def estimate(conn, %{"project_id" => _project_id} = params) do
    population = parse_int(params["population_size"], 200)
    ticks = parse_int(params["max_ticks"], 50)
    comparison = params["comparison_mode"] == "true" || params["comparison_mode"] == true
    multiplier = if comparison, do: 2, else: 1

    # Cost model: ~$0.0015 per agent per tick (based on tier distribution)
    cost_cents = population * ticks * 0.15 * multiplier
    duration_seconds = ticks * 3.5 * multiplier

    json(conn, %{
      data: %{
        estimated_cost_cents: round(cost_cents),
        estimated_duration_seconds: round(duration_seconds),
        population_size: population,
        max_ticks: ticks,
        comparison_mode: comparison
      }
    })
  end

  def approve(conn, %{"project_id" => project_id, "id" => id}) do
    case SimulationBridge.run_from_proposal(project_id, id) do
      {:ok, sim_node} ->
        json(conn, %{data: simulation_json(sim_node)})

      {:error, :not_in_proposed_status} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Simulation is not in proposed status"})
    end
  end

  def reject(conn, %{"project_id" => project_id, "id" => id}) do
    sim_node = SimulationBridge.get_product_simulation!(id)

    cond do
      to_string(sim_node.project_id) != to_string(project_id) ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})

      sim_node.status != "proposed" ->
        conn |> put_status(:conflict) |> json(%{error: "Simulation is not in proposed status"})

      true ->
        updated =
          sim_node
          |> GraphNode.changeset(%{
            status: "failed",
            attributes: Map.merge(sim_node.attributes || %{}, %{"rejected" => true})
          })
          |> HydraX.Repo.update!()

        json(conn, %{data: simulation_json(updated)})
    end
  end

  def import_results(conn, %{"project_id" => project_id, "id" => id}) do
    case SimulationBridge.import_simulation_results(project_id, id) do
      {:ok, result} ->
        json(conn, %{data: result})

      {:error, :already_imported} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Results already imported"})
    end
  end

  defp simulation_json(sim_node) do
    attrs = sim_node.attributes || %{}

    %{
      id: sim_node.id,
      project_id: sim_node.project_id,
      simulation_id: Map.get(attrs, "simulation_id"),
      scenario_summary: Map.get(attrs, "scenario_summary") || sim_node.body,
      archetype_summary: Map.get(attrs, "archetype_summary", []),
      status: sim_node.status,
      results_imported: Map.get(attrs, "results_imported", false),
      metadata: attrs,
      title: sim_node.title,
      population_size: Map.get(attrs, "population_size"),
      max_ticks: Map.get(attrs, "max_ticks"),
      comparison_mode: Map.get(attrs, "comparison_mode", false),
      inserted_at: sim_node.inserted_at,
      updated_at: sim_node.updated_at
    }
  end

  defp decision_node(d) do
    %{
      id: d.id,
      node_type: "decision",
      title: d.title,
      status: d.status,
      body: String.slice(d.body || "", 0, 200)
    }
  end

  defp requirement_node(r) do
    %{
      id: r.id,
      node_type: "requirement",
      title: r.title,
      status: r.status,
      body: String.slice(r.body || "", 0, 200)
    }
  end

  defp design_node(d) do
    %{
      id: d.id,
      node_type: "design_node",
      title: d.title,
      status: d.status,
      body: String.slice(d.body || "", 0, 200)
    }
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: [{key, value} | opts]
end
