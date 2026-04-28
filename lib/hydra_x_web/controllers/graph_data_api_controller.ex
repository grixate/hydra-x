defmodule HydraXWeb.GraphDataAPIController do
  use HydraXWeb, :controller

  import Ecto.Query
  alias HydraX.Product
  alias HydraX.Product.Graph
  alias HydraX.Product.Library

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def show(conn, %{"project_id" => project_id}) do
    project_id = parse_int(project_id)

    # Constellation §0 / Library spec §2: there is one graph. The project
    # lens shows the canonical graph (claims, decisions, requirements,
    # sources, …); the Library lens (`lens=library`) is a filtered view
    # that drops the project-graph types and includes Library structural
    # nodes (topics, authors, publications, excerpts).
    lens = conn.params["lens"]

    library_types = ~w(source topic author publication excerpt)

    # Library-only structural types — they belong to the Library lens, not
    # the project Graph (where they would just be noise around the claim
    # graph). Sources are NOT in this list — they're shared.
    library_only_types = ~w(topic author publication excerpt)

    # `signal` is a legacy alias for `source` (Graph.base_query_for/1
    # rewrites it to `where type_key = "source"`), so iterating both
    # would return the 12 source records twice. Skip the alias.
    legacy_aliases = ~w(signal)

    visible_types =
      cond do
        lens == "library" -> library_types
        true -> Graph.node_types() -- (library_only_types ++ legacy_aliases)
      end

    nodes =
      Enum.flat_map(visible_types, fn type ->
        case Graph.base_query_for(type) do
          nil ->
            []

          query ->
            try do
              base =
                query
                |> where([r], r.project_id == ^project_id)
                |> where([r], is_nil(r.archived_at))

              base
              |> HydraX.Repo.all()
              |> Enum.map(fn record ->
                attrs = Map.get(record, :attributes) || %{}

                %{
                  id: "#{type}-#{record.id}",
                  node_type: type,
                  node_id: record.id,
                  title: Map.get(record, :title, ""),
                  status: Map.get(record, :status, "") || "active",
                  body: String.slice(Map.get(record, :body, "") || "", 0, 200),
                  # Legacy field — kept for back-compat; Constellation no
                  # longer gates source visibility on it.
                  promoted_to_graph:
                    if(type in ["source", "signal"],
                      do: Map.get(attrs, "promoted_to_graph", true),
                      else: nil
                    ),
                  # Library spec §3 — surface attribute fields needed by
                  # the frontend visual hierarchy (granularity drives
                  # topic-node size; kind/ingestion_status drive source
                  # affordances).
                  granularity: Map.get(attrs, "granularity"),
                  kind: Map.get(attrs, "kind"),
                  ingestion_status: Map.get(attrs, "ingestion_status"),
                  inserted_at: Map.get(record, :inserted_at),
                  updated_at: Map.get(record, :updated_at)
                }
              end)
            rescue
              _ -> []
            end
        end
      end)

    edges = Product.list_graph_edges(project_id)

    # Filter out edges that reference nodes we dropped (hidden sources),
    # so the frontend never gets dangling edges.
    visible_ids = MapSet.new(Enum.map(nodes, & &1.id))

    edges_json =
      Enum.reduce(edges, [], fn e, acc ->
        source = "#{e.from_node_type}-#{e.from_node_id}"
        target = "#{e.to_node_type}-#{e.to_node_id}"

        if MapSet.member?(visible_ids, source) and MapSet.member?(visible_ids, target) do
          [
            %{
              id: e.id,
              source: source,
              target: target,
              kind: e.type_key,
              weight: e.weight
            }
            | acc
          ]
        else
          acc
        end
      end)
      |> Enum.reverse()

    flags =
      Graph.open_flags(project_id)
      |> Enum.map(fn flag ->
        %{
          id: flag.id,
          node_id: "#{flag.node_type}-#{flag.node_id}",
          flag_type: flag.flag_type,
          reason: flag.reason,
          status: flag.status,
          source_agent: flag.source_agent
        }
      end)

    # Count upstream (incoming) and downstream (outgoing) connections per node
    {upstream_counts, downstream_counts} =
      Enum.reduce(edges_json, {%{}, %{}}, fn e, {up, down} ->
        {
          Map.update(up, e.target, 1, &(&1 + 1)),
          Map.update(down, e.source, 1, &(&1 + 1))
        }
      end)

    # Count open flags per node
    flag_counts =
      Enum.reduce(flags, %{}, fn f, acc ->
        Map.update(acc, f.node_id, 1, &(&1 + 1))
      end)

    # Source-reference counts (spec §6: node-card source badge)
    reference_counts = Library.reference_counts_for_project(project_id)

    nodes =
      Enum.map(nodes, fn node ->
        ref_count = Map.get(reference_counts, {node.node_type, node.node_id}, 0)

        node
        |> Map.put(:upstream_count, Map.get(upstream_counts, node.id, 0))
        |> Map.put(:downstream_count, Map.get(downstream_counts, node.id, 0))
        |> Map.put(
          :connection_count,
          Map.get(upstream_counts, node.id, 0) + Map.get(downstream_counts, node.id, 0)
        )
        |> Map.put(:flag_count, Map.get(flag_counts, node.id, 0))
        |> Map.put(:source_reference_count, ref_count)
      end)

    density = Graph.density_report(project_id)

    json(conn, %{
      data: %{
        nodes: nodes,
        edges: edges_json,
        flags: flags,
        density: density,
        meta: %{
          lens: lens || "project",
          total_source_references: Enum.sum(Map.values(reference_counts))
        }
      }
    })
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value), do: String.to_integer(value)
end
