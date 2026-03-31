defmodule HydraX.Product.BoardPromotion do
  @moduledoc """
  Promotes draft board nodes to permanent graph nodes.
  """

  import Ecto.Query

  alias HydraX.Product
  alias HydraX.Product.BoardNode
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Repo

  @promotable_types ~w(insight decision strategy requirement design_node architecture_node task learning)

  @doc """
  Promote a single board node to a permanent graph node.
  Creates the corresponding graph node, updates the board node status to "promoted",
  and records the promoted_node_type and promoted_node_id.
  """
  def promote_node(board_node_id) do
    board_node_id = parse_id(board_node_id)
    board_node = Repo.get!(BoardNode, board_node_id)

    cond do
      board_node.status != "draft" ->
        {:error, :not_draft}

      board_node.node_type not in @promotable_types ->
        {:error, :not_promotable}

      true ->
        do_promote(board_node)
    end
  end

  @doc """
  Promote multiple board nodes from a session in a single transaction.
  Avoids nested transactions by inlining the promotion logic.
  """
  def promote_batch(session_id, node_ids) when is_list(node_ids) do
    session_id = parse_id(session_id)
    node_ids = Enum.map(node_ids, &parse_id/1)

    nodes =
      BoardNode
      |> where([n], n.board_session_id == ^session_id and n.id in ^node_ids and n.status == "draft")
      |> where([n], n.node_type in ^@promotable_types)
      |> Repo.all()

    Repo.transaction(fn ->
      Enum.map(nodes, fn node ->
        case do_promote_inner(node) do
          {:ok, promoted} -> promoted
          {:error, reason} -> Repo.rollback({:promotion_failed, node.id, reason})
        end
      end)
    end)
  end

  # Wrapped in a transaction for single-node promotion
  defp do_promote(board_node) do
    Repo.transaction(fn ->
      case do_promote_inner(board_node) do
        {:ok, updated_node} -> updated_node
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Core promotion logic without transaction wrapper (safe to call inside a transaction)
  defp do_promote_inner(board_node) do
    case create_graph_node(board_node) do
      {:ok, graph_node} ->
        graph_node_type = board_node.node_type
        graph_node_id = graph_node.id

        case board_node
             |> BoardNode.changeset(%{
               status: "promoted",
               promoted_node_type: graph_node_type,
               promoted_node_id: graph_node_id
             })
             |> Repo.update() do
          {:ok, updated_node} ->
            ProductPubSub.broadcast_project_event(
              board_node.project_id,
              "board_node.promoted",
              %{
                board_node: updated_node,
                graph_node_type: graph_node_type,
                graph_node_id: graph_node_id,
                board_session_id: board_node.board_session_id
              }
            )

            {:ok, updated_node}

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_graph_node(%BoardNode{} = node) do
    promotion_meta = %{
      "promoted_from_session" => node.board_session_id,
      "promoted_from_board_node" => node.id
    }

    attrs = %{
      "title" => node.title,
      "body" => node.body,
      "status" => default_graph_status(node.node_type),
      "metadata" => Map.merge(node.metadata || %{}, promotion_meta)
    }

    case node.node_type do
      "insight" ->
        # Insights require evidence_chunk_ids; use any stored in metadata or empty list
        chunk_ids = get_in(node.metadata || %{}, ["evidence_chunk_ids"]) || []
        Product.create_insight(node.project_id, Map.put(attrs, "evidence_chunk_ids", chunk_ids))

      "decision" ->
        alts = get_in(node.metadata || %{}, ["alternatives_considered"]) || []
        Product.create_decision(node.project_id, Map.put(attrs, "alternatives_considered", alts))

      "requirement" ->
        insight_ids = get_in(node.metadata || %{}, ["insight_ids"]) || []
        Product.create_requirement(node.project_id, Map.put(attrs, "insight_ids", insight_ids))

      "strategy" ->
        Product.create_strategy(node.project_id, attrs)

      "design_node" ->
        Product.create_design_node(node.project_id, attrs)

      "architecture_node" ->
        Product.create_architecture_node(node.project_id, attrs)

      "task" ->
        Product.create_task(node.project_id, attrs)

      "learning" ->
        Product.create_learning(node.project_id, attrs)
    end
  end

  defp default_graph_status("insight"), do: "accepted"
  defp default_graph_status("requirement"), do: "accepted"
  defp default_graph_status(_), do: "active"

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
end
