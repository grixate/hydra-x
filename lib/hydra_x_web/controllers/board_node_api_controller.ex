defmodule HydraXWeb.BoardNodeAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.BoardNode
  alias HydraX.Product.BoardPromotion
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"session_id" => session_id}) do
    nodes =
      Product.list_board_nodes(session_id,
        status: conn.params["status"],
        node_type: conn.params["node_type"]
      )
      |> Enum.map(&ProductPayload.board_node_json/1)

    json(conn, %{data: nodes})
  end

  def show(conn, %{"session_id" => session_id, "id" => id}) do
    node =
      session_id
      |> Product.get_session_board_node!(id)
      |> ProductPayload.board_node_json()

    json(conn, %{data: node})
  end

  def create(conn, %{"session_id" => session_id, "board_node" => params}) do
    with {:ok, %BoardNode{} = node} <- Product.create_board_node(session_id, params) do
      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.board_node_json(node)})
    end
  end

  def update(conn, %{"session_id" => session_id, "id" => id, "board_node" => params}) do
    node = Product.get_session_board_node!(session_id, id)

    with {:ok, %BoardNode{} = updated} <- Product.update_board_node(node, params) do
      json(conn, %{data: ProductPayload.board_node_json(updated)})
    end
  end

  def delete(conn, %{"session_id" => session_id, "id" => id}) do
    node = Product.get_session_board_node!(session_id, id)

    with {:ok, %BoardNode{}} <- Product.delete_board_node(node) do
      send_resp(conn, :no_content, "")
    end
  end

  def promote(conn, %{"session_id" => _session_id, "id" => id}) do
    case BoardPromotion.promote_node(id) do
      {:ok, promoted_node} ->
        json(conn, %{
          data: %{
            board_node: ProductPayload.board_node_json(promoted_node),
            promoted_node_type: promoted_node.promoted_node_type,
            promoted_node_id: promoted_node.promoted_node_id
          }
        })

      {:error, :not_draft} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Node is not in draft status"})

      {:error, :not_promotable} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Node type cannot be promoted to graph"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def promote_batch(conn, %{"session_id" => session_id, "node_ids" => node_ids}) do
    case BoardPromotion.promote_batch(session_id, node_ids) do
      {:ok, promoted_nodes} ->
        json(conn, %{
          data: %{
            promoted_count: length(promoted_nodes),
            nodes: Enum.map(promoted_nodes, &ProductPayload.board_node_json/1)
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def react(conn, %{"session_id" => _session_id, "id" => id, "reaction" => reaction, "user_id" => user_id}) do
    case Product.toggle_board_node_reaction(String.to_integer(id), reaction, user_id) do
      {:ok, updated_node} ->
        json(conn, %{data: ProductPayload.board_node_json(updated_node)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end
end
