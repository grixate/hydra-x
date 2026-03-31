defmodule HydraX.Product.PubSub do
  @moduledoc false

  alias HydraX.Product.Project
  alias HydraX.Product.Source

  def project_topic(project_or_id), do: "project:#{project_id(project_or_id)}"
  def source_topic(source_or_id), do: "source:#{source_id(source_or_id)}"
  def board_session_topic(session_or_id), do: "board_session:#{board_session_id(session_or_id)}"

  def broadcast_project_event(project_or_id, event, payload) do
    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      project_topic(project_or_id),
      {:product_project_event, event, payload}
    )
  end

  def broadcast_source_event(source_or_id, event, payload) do
    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      source_topic(source_or_id),
      {:product_source_event, event, payload}
    )
  end

  def broadcast_source_progress(%Source{} = source, status, attrs \\ %{}) do
    payload =
      attrs
      |> Map.new()
      |> Map.put(:source, source)
      |> Map.put(:status, to_string(status))

    broadcast_project_event(source.project_id, "source.#{status}", payload)
    broadcast_source_event(source.id, to_string(status), payload)
  end

  defp project_id(%Project{id: id}), do: id
  defp project_id(id) when is_integer(id), do: id
  defp project_id(id) when is_binary(id), do: String.to_integer(id)

  defp source_id(%Source{id: id}), do: id
  defp source_id(id) when is_integer(id), do: id
  defp source_id(id) when is_binary(id), do: String.to_integer(id)

  defp board_session_id(%HydraX.Product.BoardSession{id: id}), do: id
  defp board_session_id(id) when is_integer(id), do: id
  defp board_session_id(id) when is_binary(id), do: String.to_integer(id)
end
