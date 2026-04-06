defmodule HydraXWeb.SimulationAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product.SimulationBridge
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    simulations = SimulationBridge.list_product_simulations(project_id)
    json(conn, %{data: Enum.map(simulations, &simulation_json/1)})
  end

  def create(conn, %{"project_id" => project_id} = params) do
    opts =
      []
      |> maybe_add(:metadata, params["metadata"])

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
          |> HydraX.Product.SimulationNode.changeset(%{
            "status" => "failed",
            "metadata" => Map.merge(sim_node.metadata || %{}, %{"rejected" => true})
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
    %{
      id: sim_node.id,
      project_id: sim_node.project_id,
      simulation_id: sim_node.simulation_id,
      scenario_summary: sim_node.scenario_summary,
      archetype_summary: sim_node.archetype_summary,
      status: sim_node.status,
      results_imported: sim_node.results_imported,
      metadata: sim_node.metadata || %{},
      inserted_at: sim_node.inserted_at,
      updated_at: sim_node.updated_at
    }
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: [{key, value} | opts]
end
