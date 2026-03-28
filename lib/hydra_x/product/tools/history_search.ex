defmodule HydraX.Product.Tools.HistorySearch do
  @behaviour HydraX.Tool

  import Ecto.Query

  alias HydraX.Product.Graph
  alias HydraX.Product.GraphEdge
  alias HydraX.Repo

  @impl true
  def name, do: "history_search"

  @impl true
  def description, do: "Search for node revision history via supersedes edges"

  @impl true
  def safety_classification, do: "product_read"

  @impl true
  def tool_schema do
    %{
      name: "history_search",
      description:
        "Search for nodes matching a query and return their revision history using 'supersedes' edges and update ordering.",
      input_schema: %{
        type: "object",
        properties: %{
          node_type: %{type: "string", description: "Node type to search"},
          node_id: %{type: "integer", description: "Node ID to get history for"},
          query: %{type: "string", description: "Optional search query"}
        },
        required: ["node_type", "node_id"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params) do
      node_type = to_string(params[:node_type] || params["node_type"])
      node_id = params[:node_id] || params["node_id"]

      # Find supersedes chain (older versions)
      superseded_by =
        GraphEdge
        |> where(
          [e],
          e.project_id == ^project_id and
            e.to_node_type == ^node_type and
            e.to_node_id == ^node_id and
            e.kind == "supersedes"
        )
        |> Repo.all()

      supersedes =
        GraphEdge
        |> where(
          [e],
          e.project_id == ^project_id and
            e.from_node_type == ^node_type and
            e.from_node_id == ^node_id and
            e.kind == "supersedes"
        )
        |> Repo.all()

      # Resolve all nodes in the chain
      current = resolve_with_meta(node_type, node_id)

      predecessors =
        superseded_by
        |> Enum.map(fn e -> resolve_with_meta(e.from_node_type, e.from_node_id) end)
        |> Enum.reject(&is_nil/1)

      successors =
        supersedes
        |> Enum.map(fn e -> resolve_with_meta(e.to_node_type, e.to_node_id) end)
        |> Enum.reject(&is_nil/1)

      {:ok,
       %{
         history: %{
           current: current,
           predecessors: predecessors,
           successors: successors,
           total_versions: 1 + length(predecessors) + length(successors)
         }
       }}
    end
  end

  @impl true
  def result_summary(%{history: h}), do: "#{h.total_versions} versions found"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp resolve_with_meta(node_type, node_id) do
    case Graph.resolve_node(node_type, node_id) do
      {:ok, nil} -> nil
      {:ok, record} ->
        %{
          node_type: node_type,
          node_id: node_id,
          title: Map.get(record, :title, ""),
          status: Map.get(record, :status, ""),
          updated_at: Map.get(record, :updated_at)
        }
      _ -> nil
    end
  end

  defp extract_project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end
      _ -> {:error, :product_project_context_required}
    end
  end
end
