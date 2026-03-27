defmodule HydraX.Product.Citations do
  @moduledoc false

  import Ecto.Query

  alias HydraX.Product.SourceChunk
  alias HydraX.Repo

  @citation_pattern ~r/\[\[cite:(\d+)\]\]/

  def parse(project_id, content) when is_integer(project_id) and is_binary(content) do
    chunk_ids =
      @citation_pattern
      |> Regex.scan(content)
      |> Enum.map(fn [_match, value] -> String.to_integer(value) end)
      |> Enum.uniq()

    citations = citation_payloads(project_id, chunk_ids)

    index_by_chunk_id =
      citations
      |> Map.new(fn citation -> {citation.chunk_id, citation.index} end)

    rendered =
      Regex.replace(@citation_pattern, content, fn _full, raw_id ->
        case Map.get(index_by_chunk_id, String.to_integer(raw_id)) do
          nil -> "[?]"
          index -> "[#{index}]"
        end
      end)

    {rendered, citations}
  end

  def parse(_project_id, content) when is_binary(content), do: {content, []}

  defp citation_payloads(_project_id, []), do: []

  defp citation_payloads(project_id, chunk_ids) do
    chunks =
      SourceChunk
      |> join(:inner, [chunk], source in assoc(chunk, :source))
      |> where([chunk, _source], chunk.project_id == ^project_id and chunk.id in ^chunk_ids)
      |> preload([_chunk, source], source: source)
      |> Repo.all()
      |> Map.new(fn chunk -> {chunk.id, chunk} end)

    chunk_ids
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk_id, index} ->
      case Map.get(chunks, chunk_id) do
        nil ->
          nil

        chunk ->
          %{
            index: index,
            chunk_id: chunk.id,
            source_id: chunk.source_id,
            source_title: chunk.source.title,
            section: get_in(chunk.metadata || %{}, ["section"]),
            excerpt: String.slice(chunk.content, 0, 280)
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
