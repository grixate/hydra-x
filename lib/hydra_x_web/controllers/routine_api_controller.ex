defmodule HydraXWeb.RoutineAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Routine
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    routines =
      Product.list_routines(project_id, status: conn.params["status"])
      |> Enum.map(&ProductPayload.routine_json/1)

    json(conn, %{data: routines})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    routine = project_id |> Product.get_project_routine!(id) |> ProductPayload.routine_json()
    json(conn, %{data: routine})
  end

  def create(conn, %{"project_id" => project_id, "routine" => params}) do
    with {:ok, %Routine{} = routine} <- Product.create_routine(project_id, params) do
      conn |> put_status(:created) |> json(%{data: ProductPayload.routine_json(routine)})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "routine" => params}) do
    routine = Product.get_project_routine!(project_id, id)
    with {:ok, %Routine{} = updated} <- Product.update_routine(routine, params) do
      json(conn, %{data: ProductPayload.routine_json(updated)})
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    routine = Product.get_project_routine!(project_id, id)
    with {:ok, %Routine{}} <- Product.delete_routine(routine) do
      send_resp(conn, :no_content, "")
    end
  end

  def runs(conn, %{"project_id" => project_id, "id" => id}) do
    routine = Product.get_project_routine!(project_id, id)
    limit = parse_limit(conn.params["limit"])

    runs =
      Product.list_routine_runs(routine.id, limit: limit)
      |> Enum.map(&ProductPayload.routine_run_json/1)

    json(conn, %{data: runs})
  end

  def run(conn, %{"project_id" => project_id, "id" => id}) do
    routine = Product.get_project_routine!(project_id, id)

    case Product.create_routine_run(%{
      "routine_id" => routine.id,
      "started_at" => DateTime.utc_now(),
      "status" => "running"
    }) do
      {:ok, run} ->
        conn |> put_status(:created) |> json(%{data: ProductPayload.routine_run_json(run)})
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp parse_limit(nil), do: 20
  defp parse_limit(value) when is_integer(value), do: value
  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> min(int, 100)
      _ -> 20
    end
  end
  defp parse_limit(_), do: 20
end
