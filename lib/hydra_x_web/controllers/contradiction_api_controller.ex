defmodule HydraXWeb.ContradictionAPIController do
  use HydraXWeb, :controller

  alias HydraX.Coherence

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    case parse_int_strict(params["limit"]) do
      :invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_limit", value: params["limit"]})

      limit ->
        opts =
          [
            status: params["status"] |> parse_status_filter(),
            min_severity: params["min_severity"],
            limit: limit
          ]
          |> Enum.reject(fn {_, v} -> is_nil(v) end)

        items =
          project_id
          |> Coherence.list_for_project(opts)
          |> Enum.map(&serialize/1)

        json(conn, %{data: items})
    end
  end

  @doc """
  Graph-overlay badge counts: for each `{node_type, node_id}` pair in a
  project that has visible contradictions, return the severity mix.
  Used by the graph renderer to draw the red/yellow dot.
  """
  def badges(conn, %{"project_id" => project_id}) do
    counts = Coherence.badge_counts_for_project(project_id)

    items =
      Enum.map(counts, fn {{node_type, node_id}, severities} ->
        %{
          node_type: node_type,
          node_id: node_id,
          total: length(severities),
          high: Enum.count(severities, &(&1 == "high")),
          medium: Enum.count(severities, &(&1 == "medium")),
          low: Enum.count(severities, &(&1 == "low"))
        }
      end)

    json(conn, %{data: items})
  end

  def show(conn, %{"project_id" => _project_id, "id" => id}) do
    case Coherence.get(id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
      contradiction -> json(conn, %{data: serialize(contradiction)})
    end
  end

  def dismiss(conn, %{"project_id" => _pid, "id" => id} = params) do
    contradiction = Coherence.get!(id)

    case Coherence.dismiss(contradiction, reason: params["reason"], user_id: params["user_id"]) do
      {:ok, updated} -> json(conn, %{data: serialize(updated)})
      err -> error_response(conn, err)
    end
  end

  def resolve(conn, %{"project_id" => _pid, "id" => id} = params) do
    contradiction = Coherence.get!(id)

    case Coherence.resolve(contradiction, reason: params["reason"], user_id: params["user_id"]) do
      {:ok, updated} -> json(conn, %{data: serialize(updated)})
      err -> error_response(conn, err)
    end
  end

  def acknowledge_tension(conn, %{"project_id" => _pid, "id" => id} = params) do
    contradiction = Coherence.get!(id)

    case Coherence.acknowledge_tension(contradiction, reason: params["reason"]) do
      {:ok, updated} -> json(conn, %{data: serialize(updated)})
      err -> error_response(conn, err)
    end
  end

  defp serialize(c) do
    %{
      id: c.id,
      project_id: c.project_id,
      shared_scope_id: c.shared_scope_id,
      mode: c.mode,
      node_a: %{type: c.node_a_type, id: c.node_a_id, scope: c.node_a_scope},
      node_b: %{type: c.node_b_type, id: c.node_b_id, scope: c.node_b_scope},
      explanation: c.explanation,
      severity: c.severity,
      severity_reason: c.severity_reason,
      confidence: c.confidence,
      context_diff: c.context_diff,
      suggested_resolutions: c.suggested_resolutions,
      status: c.status,
      status_reason: c.status_reason,
      resolved_at: c.resolved_at,
      detected_at: c.detected_at,
      last_confirmed_at: c.last_confirmed_at,
      dismissed_count: c.dismissed_count,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  defp parse_status_filter(nil), do: nil
  defp parse_status_filter(""), do: nil
  defp parse_status_filter(status) when is_binary(status), do: status

  # Returns `nil` for absent, a positive integer for valid input, or
  # `:invalid` — never silently coerces garbage to the default.
  defp parse_int_strict(nil), do: nil
  defp parse_int_strict(""), do: nil
  defp parse_int_strict(v) when is_integer(v) and v > 0, do: v
  defp parse_int_strict(v) when is_integer(v), do: :invalid

  defp parse_int_strict(v) when is_binary(v) do
    case Integer.parse(v) do
      {int, ""} when int > 0 -> int
      _ -> :invalid
    end
  end

  defp parse_int_strict(_), do: :invalid

  defp error_response(conn, {:error, changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "invalid",
      details:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {k, v}, acc ->
            String.replace(acc, "%{#{k}}", to_string(v))
          end)
        end)
    })
  end
end
