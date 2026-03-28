defmodule HydraX.Product.ConversationGraph do
  @moduledoc """
  Detects graph mutations from agent tool use within conversations and provides
  context for rendering inline cards in the frontend.
  """

  import Ecto.Query

  alias HydraX.Product.ProductMessage
  alias HydraX.Repo

  @mutation_tools ~w(insight_create insight_update requirement_create architecture_create architecture_update design_create design_update)

  def extract_graph_mutations(conversation_id) do
    ProductMessage
    |> where([m], m.product_conversation_id == ^conversation_id and m.role == "assistant")
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.flat_map(&extract_mutations_from_message/1)
  end

  def conversation_nodes(conversation_id) do
    mutations = extract_graph_mutations(conversation_id)

    mutations
    |> Enum.map(fn m -> {m.node_type, m.node_id} end)
    |> Enum.uniq()
  end

  # -------------------------------------------------------------------
  # Marker parsing
  # -------------------------------------------------------------------

  @decision_gate_regex ~r/\[\[decision_gate:(.+?)\]\]/
  @handoff_regex ~r/\[\[handoff:(.+?)\]\]/

  def parse_decision_gates(content) when is_binary(content) do
    Regex.scan(@decision_gate_regex, content)
    |> Enum.map(fn [_full, title] -> %{title: String.trim(title)} end)
  end

  def parse_decision_gates(_), do: []

  def parse_handoffs(content) when is_binary(content) do
    Regex.scan(@handoff_regex, content)
    |> Enum.map(fn [_full, persona] -> %{persona: String.trim(persona)} end)
  end

  def parse_handoffs(_), do: []

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp extract_mutations_from_message(%ProductMessage{} = message) do
    metadata = message.metadata || %{}
    tool_results = Map.get(metadata, "tool_results", [])

    Enum.flat_map(tool_results, fn result ->
      tool_name = Map.get(result, "tool_name", "")

      if tool_name in @mutation_tools do
        node_type = infer_node_type(tool_name)
        node_id = get_in(result, ["result", "id"]) || get_in(result, ["result", node_type, "id"])
        action = if String.contains?(tool_name, "create"), do: "created", else: "updated"

        if node_id do
          [%{node_type: node_type, node_id: node_id, action: action, tool_name: tool_name}]
        else
          []
        end
      else
        []
      end
    end)
  end

  defp infer_node_type("insight_create"), do: "insight"
  defp infer_node_type("insight_update"), do: "insight"
  defp infer_node_type("requirement_create"), do: "requirement"
  defp infer_node_type("architecture_create"), do: "architecture_node"
  defp infer_node_type("architecture_update"), do: "architecture_node"
  defp infer_node_type("design_create"), do: "design_node"
  defp infer_node_type("design_update"), do: "design_node"
  defp infer_node_type(_), do: "unknown"
end
