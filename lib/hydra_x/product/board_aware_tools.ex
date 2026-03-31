defmodule HydraX.Product.BoardAwareTools do
  @moduledoc """
  Redirects node creation to board nodes when a board_session_id is present in params.
  """

  alias HydraX.Product

  @doc """
  Check if the tool call is within a board session context.
  Returns the board_session_id if present, nil otherwise.
  """
  def board_session_id(params) do
    params[:board_session_id] || params["board_session_id"]
  end

  @doc """
  Create a board node instead of a permanent graph node.
  Returns a result in the same format as the original tool would.
  """
  def create_board_node(session_id, node_type, params) do
    attrs = %{
      "node_type" => node_type,
      "title" => params[:title] || params["title"],
      "body" => params[:body] || params["body"],
      "created_by" => "agent",
      "metadata" => extract_metadata(node_type, params)
    }

    case Product.create_board_node(session_id, attrs) do
      {:ok, board_node} ->
        {:ok,
         %{
           board_node: %{
             id: board_node.id,
             node_type: board_node.node_type,
             title: board_node.title,
             status: "draft",
             board_session_id: board_node.board_session_id
           },
           note: "Created as draft board node. Promote to graph when ready."
         }}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_metadata("decision", params) do
    %{
      "alternatives_considered" =>
        params[:alternatives_considered] || params["alternatives_considered"] || [],
      "decided_by" => "agent"
    }
  end

  defp extract_metadata("insight", params) do
    %{
      "evidence_chunk_ids" =>
        params[:evidence_chunk_ids] || params["evidence_chunk_ids"] || []
    }
  end

  defp extract_metadata("requirement", params) do
    %{
      "insight_ids" => params[:insight_ids] || params["insight_ids"] || []
    }
  end

  defp extract_metadata("architecture_node", params) do
    %{
      "node_type" => params[:node_type] || params["node_type"] || "system_design"
    }
  end

  defp extract_metadata("design_node", params) do
    %{
      "node_type" => params[:node_type] || params["node_type"] || "user_flow"
    }
  end

  defp extract_metadata(_node_type, _params), do: %{}

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
