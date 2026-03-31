defmodule HydraXWeb.BoardSessionChannel do
  use HydraXWeb, :channel

  alias HydraX.Product
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraXWeb.BoardPresence
  alias HydraXWeb.ProductChannelAuth
  alias HydraXWeb.ProductPayload

  @impl true
  def join("board_session:" <> raw_id, params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         :ok <- ProductChannelAuth.allow_sandbox(socket),
         session <- Product.get_board_session!(String.to_integer(raw_id)) do
      Phoenix.PubSub.subscribe(
        HydraX.PubSub,
        ProductPubSub.board_session_topic(session.id)
      )

      Phoenix.PubSub.subscribe(
        HydraX.PubSub,
        ProductPubSub.project_topic(session.project_id)
      )

      user_id = params["user_id"] || "operator"
      user_name = params["user_name"] || "Operator"

      send(self(), :after_join)

      {:ok, ProductPayload.board_session_json(session),
       socket
       |> assign(:board_session_id, session.id)
       |> assign(:project_id, session.project_id)
       |> assign(:user_id, user_id)
       |> assign(:user_name, user_name)}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  rescue
    Ecto.NoResultsError -> {:error, %{reason: "not_found"}}
  end

  @impl true
  def handle_info(:after_join, socket) do
    BoardPresence.track(socket, socket.assigns.user_id, %{
      name: socket.assigns.user_name,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    push(socket, "presence_state", BoardPresence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:product_project_event, event, payload}, socket) do
    board_session_id = socket.assigns.board_session_id

    case event do
      "board_node." <> _ ->
        if Map.get(payload, :board_session_id) == board_session_id do
          push(socket, event, board_event_json(event, payload))
        end

      "board_session." <> _ ->
        push(socket, event, board_event_json(event, payload))

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Client events ---

  @impl true
  def handle_in("cursor_move", %{"x" => x, "y" => y}, socket) do
    broadcast_from(socket, "cursor_move", %{
      user_id: socket.assigns.user_id,
      x: x,
      y: y
    })

    {:noreply, socket}
  end

  def handle_in("node_moved", %{"node_id" => node_id, "x" => x, "y" => y}, socket) do
    node_id = to_integer(node_id)
    node = Product.get_board_node!(node_id)
    position = %{"x" => x, "y" => y}
    updated_metadata = Map.put(node.metadata || %{}, "position", position)

    case Product.update_board_node(node, %{"metadata" => updated_metadata}) do
      {:ok, _updated} ->
        broadcast_from(socket, "node_moved", %{node_id: node_id, x: x, y: y})
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  rescue
    Ecto.NoResultsError -> {:noreply, socket}
  end

  def handle_in("reaction_toggled", %{"node_id" => node_id, "reaction" => reaction}, socket) do
    node_id = to_integer(node_id)

    case Product.toggle_board_node_reaction(node_id, reaction, socket.assigns.user_id) do
      {:ok, updated_node} ->
        broadcast(socket, "reaction_toggled", %{
          node_id: node_id,
          reactions: get_in(updated_node.metadata || %{}, ["reactions"]) || %{}
        })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_in("typing_start", _payload, socket) do
    broadcast_from(socket, "typing_start", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  def handle_in("typing_stop", _payload, socket) do
    broadcast_from(socket, "typing_stop", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  # --- JSON helpers ---

  defp board_event_json("board_node.created", %{board_node: node}) do
    %{board_node: ProductPayload.board_node_json(node)}
  end

  defp board_event_json("board_node.promoted", payload) do
    %{
      board_node: ProductPayload.board_node_json(payload.board_node),
      graph_node_type: payload.graph_node_type,
      graph_node_id: payload.graph_node_id
    }
  end

  defp board_event_json("board_node.reaction_toggled", payload) do
    %{
      board_node_id: payload.board_node_id,
      reaction: payload.reaction,
      user_id: payload.user_id,
      reactions: payload.reactions
    }
  end

  defp board_event_json(_event, payload) do
    %{payload: inspect(payload, limit: 8)}
  end

  defp to_integer(v) when is_integer(v), do: v
  defp to_integer(v) when is_binary(v), do: String.to_integer(v)
end
