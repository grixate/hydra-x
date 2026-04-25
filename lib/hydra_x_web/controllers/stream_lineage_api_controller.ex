defmodule HydraXWeb.StreamLineageAPIController do
  @moduledoc """
  Lineage + Why prose for a Stream item, feeding the spotlight modal
  (stream-visual-design-spec v3 §3). Resolves the item's referenced node
  (or pair of nodes for contradictions), reuses `WhyProse.build/4` for a
  cached lineage + prose, and returns a compact chain the frontend can
  render as a horizontal visual.
  """

  use HydraXWeb, :controller

  import Ecto.Query

  alias HydraX.Coherence.Contradiction
  alias HydraX.Product.Graph
  alias HydraX.Product.WhyProse
  alias HydraX.Repo

  action_fallback HydraXWeb.ProjectAPIFallbackController

  # Ordering for the generic `context_type = "node"` fallback lookup: we
  # try each specific table in turn until a row with the given id matches.
  @node_type_scan ~w(insight decision requirement strategy architecture_node design_node constraint learning task knowledge_entry routine source)

  def show(conn, %{"project_id" => project_id} = params) do
    project_id = parse_int(project_id)

    case resolve_references(project_id, params) do
      [] ->
        json(conn, %{data: empty_payload()})

      [primary] ->
        json(conn, %{data: lineage_for(project_id, primary)})

      [primary, secondary] ->
        a = lineage_for(project_id, primary)
        b = lineage_for(project_id, secondary)

        json(conn, %{
          data: %{
            chain: a.chain,
            why: a.why,
            node_type: a.node_type,
            node_id: a.node_id,
            chain_b: b.chain
          }
        })
    end
  end

  # Resolve one or two (node_type, node_id) pairs from the item's params.
  # For a contradiction, returns the two referenced nodes. Otherwise returns
  # the single referenced node when resolvable, or [] when not.
  defp resolve_references(project_id, params) do
    cond do
      params["kind"] == "contradiction" ->
        resolve_contradiction_nodes(project_id, params)

      true ->
        case resolve_single_node(params["context_type"], params["context_id"]) do
          nil -> []
          {type, id} -> [{type, id}]
        end
    end
  end

  defp resolve_contradiction_nodes(project_id, params) do
    # The stream item's context_id is the Contradiction row itself (seeded
    # this way by `maybe_contradiction_item` in StreamTabs). Look it up to
    # get node_a + node_b.
    with id when is_integer(id) <- parse_int(params["context_id"]),
         %Contradiction{} = c <- Repo.get_by(Contradiction, id: id, project_id: project_id) do
      [
        {c.node_a_type, c.node_a_id},
        {c.node_b_type, c.node_b_id}
      ]
    else
      _ -> []
    end
  end

  defp resolve_single_node(nil, _), do: nil
  defp resolve_single_node(_, nil), do: nil

  defp resolve_single_node(context_type, context_id_raw) do
    with id when is_integer(id) <- parse_int(context_id_raw) do
      do_resolve(context_type, id)
    else
      _ -> nil
    end
  end

  # Specific node type — trust it.
  defp do_resolve(type, id) when type in @node_type_scan do
    case Graph.resolve_node(type, id) do
      {:ok, record} when not is_nil(record) -> {type, id}
      _ -> nil
    end
  end

  # Generic "node" — scan known schemas until a row with this id is found.
  # O(n) schemas but each lookup is a primary-key fetch, so cheap.
  defp do_resolve("node", id) do
    Enum.find_value(@node_type_scan, fn type ->
      case Graph.resolve_node(type, id) do
        {:ok, record} when not is_nil(record) -> {type, id}
        _ -> nil
      end
    end)
  end

  # Non-graph contexts (source/session/flow/task) don't produce a lineage.
  defp do_resolve(_, _), do: nil

  defp lineage_for(project_id, {node_type, node_id}) do
    case WhyProse.build(project_id, node_type, node_id, skip_prose: false) do
      {:ok, %{lineage: cards, prose: prose}} ->
        %{
          chain: Enum.map(cards, &card_to_chain_node/1),
          why: prose,
          why_structured: parse_structured(prose),
          node_type: node_type,
          node_id: node_id
        }

      {:error, _} ->
        %{
          chain: [],
          why: nil,
          why_structured: nil,
          node_type: node_type,
          node_id: node_id
        }
    end
  end

  # Split the generator's output into {root, path, summary}. The prompt
  # requests exactly three blank-line-separated paragraphs, but we accept
  # degraded shapes (1 or 2 paragraphs) to stay resilient to LLM drift
  # and to handle cached prose emitted before the v2 prompt.
  defp parse_structured(nil), do: nil
  defp parse_structured(""), do: nil

  defp parse_structured(prose) when is_binary(prose) do
    paragraphs =
      prose
      |> String.split(~r/\n\s*\n/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case paragraphs do
      [root, path, summary | _] -> %{root: root, path: path, summary: summary}
      [root, summary] -> %{root: root, path: nil, summary: summary}
      [single] -> single_paragraph_fallback(single)
      [] -> nil
    end
  end

  # Legacy prose was a single run-on paragraph ending with "So X exists
  # because Y." Split on that sentence so older cached rows still render
  # in the new structured layout.
  defp single_paragraph_fallback(text) do
    case Regex.run(~r/^(.*?)(So\s+.*?\.)\s*$/s, text) do
      [_, head, tail] -> %{root: String.trim(head), path: nil, summary: String.trim(tail)}
      _ -> %{root: text, path: nil, summary: nil}
    end
  end

  defp card_to_chain_node(%{} = card) do
    %{
      id: Map.get(card, :node_id) || 0,
      type: Map.get(card, :node_type) || "node",
      title: Map.get(card, :title) || "(untitled)",
      relation: Map.get(card, :edge_kind)
    }
  end

  defp empty_payload do
    %{chain: [], why: nil, node_type: nil, node_id: nil}
  end

  defp parse_int(nil), do: nil
  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end
end
