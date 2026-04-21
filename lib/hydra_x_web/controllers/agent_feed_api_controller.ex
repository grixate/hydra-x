defmodule HydraXWeb.AgentFeedAPIController do
  use HydraXWeb, :controller

  import Ecto.Query

  alias HydraX.Product.{Insight, Decision, Strategy, Requirement, DesignNode, ArchitectureNode}
  alias HydraX.Product.{Learning, Artifact}
  alias HydraX.Repo

  action_fallback HydraXWeb.ProjectAPIFallbackController

  @persona_schemas %{
    "researcher" => [{Insight, "insight"}],
    "strategist" => [{Decision, "decision"}, {Requirement, "requirement"}, {Strategy, "strategy"}],
    "architect" => [{ArchitectureNode, "architecture_node"}],
    "designer" => [{DesignNode, "design_node"}],
    "memory_agent" => [{Learning, "learning"}]
  }

  @accepted_statuses ~w(accepted active done)

  def show(conn, %{"project_id" => project_id, "persona" => persona} = params) do
    project_id = parse_int(project_id)
    limit = parse_int(params["limit"] || "20")
    offset = parse_int(params["offset"] || "0")

    schemas = Map.get(@persona_schemas, persona, [])

    # Fetch nodes for this persona (without edge counts — added after pagination)
    nodes =
      Enum.flat_map(schemas, fn {schema, node_type} ->
        schema
        |> where([n], n.project_id == ^project_id)
        |> order_by([n], desc: n.inserted_at)
        |> Repo.all()
        |> Enum.map(fn record ->
          body = Map.get(record, :body) || Map.get(record, :content) || Map.get(record, :description) || ""

          %{
            type: "node",
            node_type: node_type,
            node_id: record.id,
            title: Map.get(record, :title, ""),
            body: String.slice(body, 0, 400),
            status: Map.get(record, :status, ""),
            flag_count: 0,
            origin: "project",
            origin_title: nil,
            created_at: record.inserted_at
          }
        end)
      end)

    # Fetch artifacts for this persona
    artifacts =
      try do
        Artifact
        |> where([a], a.project_id == ^project_id)
        |> order_by([a], desc: a.updated_at)
        |> limit(5)
        |> Repo.all()
        |> Enum.map(fn a ->
          %{
            type: "artifact",
            artifact_id: a.id,
            title: Map.get(a, :title, ""),
            version: Map.get(a, :version, 1),
            change_summary: get_in(a.metadata || %{}, ["change_summary"]),
            updated_at: a.updated_at
          }
        end)
      rescue
        _ -> []
      end

    # Combine and sort by date
    all_items =
      (nodes ++ artifacts)
      |> Enum.sort_by(fn item ->
        case item do
          %{created_at: dt} when not is_nil(dt) -> dt
          %{updated_at: dt} when not is_nil(dt) -> dt
          _ -> ~U[2000-01-01 00:00:00Z]
        end
      end, {:desc, DateTime})

    total_count = length(all_items)

    # Paginate, then enrich only visible items with edge counts
    items =
      all_items
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn item ->
        if item.type == "node" do
          Map.merge(item, %{
            upstream_count: count_edges(project_id, item.node_type, item.node_id, :upstream),
            downstream_count: count_edges(project_id, item.node_type, item.node_id, :downstream),
          })
        else
          item
        end
      end)

    # Compute stats
    total_created = length(nodes)
    total_accepted = Enum.count(nodes, fn n -> n.status in @accepted_statuses end)
    total_rejected = Enum.count(nodes, fn n -> n.status in ~w(rejected) end)
    total_pending = Enum.count(nodes, fn n -> n.status in ~w(draft pending) end)
    rate = if total_created > 0, do: Float.round(total_accepted / total_created, 2), else: 0.0

    by_node_type =
      nodes
      |> Enum.group_by(& &1.node_type)
      |> Map.new(fn {type, list} -> {type, length(list)} end)

    # Heatmap placeholder (deterministic per persona)
    seed = persona |> String.to_charlist() |> Enum.sum()
    heatmap =
      for di <- 0..6 do
        for hi <- 0..23 do
          v = rem(seed * (di + 1) * (hi + 1) * 17, 100)
          if v < 15, do: div(v, 4) + 1, else: 0
        end
      end

    # Last active
    last_active = last_active_for_persona(project_id, persona)

    json(conn, %{
      data: %{
        items: items,
        stats: %{
          nodes_created: total_created,
          nodes_accepted: total_accepted,
          nodes_rejected: total_rejected,
          nodes_pending: total_pending,
          acceptance_rate: rate,
          by_node_type: by_node_type,
          spend_cents: 0,
          tokens: 0,
          tokens_in: 0,
          tokens_out: 0,
          call_count: 0,
          activity_heatmap: heatmap,
          last_active_at: last_active
        },
        total_count: total_count
      }
    })
  end

  defp count_edges(project_id, node_type, node_id, :upstream) do
    HydraX.Product.GraphEdge
    |> where([e],
      e.project_id == ^project_id and
        e.to_node_type == ^to_string(node_type) and
        e.to_node_id == ^node_id
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_edges(project_id, node_type, node_id, :downstream) do
    HydraX.Product.GraphEdge
    |> where([e],
      e.project_id == ^project_id and
        e.from_node_type == ^to_string(node_type) and
        e.from_node_id == ^node_id
    )
    |> Repo.aggregate(:count, :id)
  end

  defp last_active_for_persona(project_id, persona) do
    alias HydraX.Product.ProductConversation
    alias HydraX.Product.ProductMessage

    ProductConversation
    |> where([c], c.project_id == ^project_id and c.persona == ^persona)
    |> join(:left, [c], m in ProductMessage, on: m.product_conversation_id == c.id)
    |> select([_c, m], max(m.inserted_at))
    |> Repo.one()
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
