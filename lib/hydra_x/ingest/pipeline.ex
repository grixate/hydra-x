defmodule HydraX.Ingest.Pipeline do
  @moduledoc """
  Orchestrates document ingestion: parse file → deduplicate → create memory entries.
  """

  require Logger

  alias HydraX.Ingest.Parser
  alias HydraX.Memory

  import Ecto.Query

  @default_importance 0.4
  @entry_type "Observation"

  @doc """
  Ingest a file for the given agent. Parses the file into chunks,
  deduplicates via content_hash, and creates memory entries.

  Returns `{:ok, %{created: count, skipped: count, archived: count}}`.
  """
  def ingest_file(agent_id, file_path) do
    filename = Path.basename(file_path)

    case Parser.parse(file_path) do
      {:ok, chunks} ->
        existing = existing_hashes(agent_id, filename)
        new_hashes = MapSet.new(chunks, fn c -> c.metadata["content_hash"] end)

        # Archive stale entries (hash no longer present in updated file)
        archived = archive_stale_entries(agent_id, filename, existing, new_hashes)

        # Create new entries (hash not yet in DB)
        {created, skipped} =
          Enum.reduce(chunks, {0, 0}, fn chunk, {created_count, skipped_count} ->
            hash = chunk.metadata["content_hash"]

            if MapSet.member?(existing, hash) do
              # Already exists, skip
              {created_count, skipped_count + 1}
            else
              attrs = %{
                agent_id: agent_id,
                type: @entry_type,
                status: "active",
                content: chunk.content,
                importance: @default_importance,
                metadata:
                  Map.merge(chunk.metadata, %{
                    "source" => "ingest",
                    "ingested_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                  })
              }

              case Memory.create_memory(attrs) do
                {:ok, _entry} ->
                  {created_count + 1, skipped_count}

                {:error, reason} ->
                  Logger.warning("Failed to ingest chunk from #{filename}: #{inspect(reason)}")
                  {created_count, skipped_count}
              end
            end
          end)

        Logger.info(
          "Ingest complete: #{filename} → #{created} created, #{skipped} skipped, #{archived} archived"
        )

        {:ok, %{created: created, skipped: skipped, archived: archived}}

      {:error, reason} ->
        Logger.warning("Failed to parse #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Archive all memory entries for a deleted ingest file.
  """
  def archive_file(agent_id, filename) do
    count = archive_all_entries(agent_id, filename)
    Logger.info("Archived #{count} entries for deleted file: #{filename}")
    {:ok, count}
  end

  @doc """
  List files that have been ingested for an agent (based on memory entry metadata).
  """
  def list_ingested_files(agent_id) do
    HydraX.Memory.Entry
    |> where([e], e.agent_id == ^agent_id and e.status == "active")
    |> where([e], fragment("json_extract(?, '$.source')", e.metadata) == "ingest")
    |> select(
      [e],
      {fragment("json_extract(?, '$.source_file')", e.metadata),
       count(e.id)}
    )
    |> group_by([e], fragment("json_extract(?, '$.source_file')", e.metadata))
    |> HydraX.Repo.all()
    |> Enum.map(fn {file, count} -> %{file: file, entries: count} end)
  end

  # -- Private helpers --

  defp existing_hashes(agent_id, filename) do
    HydraX.Memory.Entry
    |> where([e], e.agent_id == ^agent_id and e.status == "active")
    |> where([e], fragment("json_extract(?, '$.source')", e.metadata) == "ingest")
    |> where([e], fragment("json_extract(?, '$.source_file')", e.metadata) == ^filename)
    |> select([e], fragment("json_extract(?, '$.content_hash')", e.metadata))
    |> HydraX.Repo.all()
    |> MapSet.new()
  end

  defp archive_stale_entries(agent_id, filename, existing_hashes, new_hashes) do
    stale_hashes = MapSet.difference(existing_hashes, new_hashes)

    if MapSet.size(stale_hashes) > 0 do
      stale_list = MapSet.to_list(stale_hashes)

      {count, _} =
        HydraX.Memory.Entry
        |> where([e], e.agent_id == ^agent_id and e.status == "active")
        |> where([e], fragment("json_extract(?, '$.source')", e.metadata) == "ingest")
        |> where([e], fragment("json_extract(?, '$.source_file')", e.metadata) == ^filename)
        |> where(
          [e],
          fragment("json_extract(?, '$.content_hash')", e.metadata) in ^stale_list
        )
        |> HydraX.Repo.update_all(set: [status: "archived"])

      count
    else
      0
    end
  end

  defp archive_all_entries(agent_id, filename) do
    {count, _} =
      HydraX.Memory.Entry
      |> where([e], e.agent_id == ^agent_id and e.status == "active")
      |> where([e], fragment("json_extract(?, '$.source')", e.metadata) == "ingest")
      |> where([e], fragment("json_extract(?, '$.source_file')", e.metadata) == ^filename)
      |> HydraX.Repo.update_all(set: [status: "archived"])

    count
  end
end
