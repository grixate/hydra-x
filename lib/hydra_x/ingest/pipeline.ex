defmodule HydraX.Ingest.Pipeline do
  @moduledoc """
  Orchestrates document ingestion: parse file → deduplicate → create memory entries.
  """

  require Logger

  alias HydraX.Ingest.Run
  alias HydraX.Ingest.Parser
  alias HydraX.Memory
  alias HydraX.Runtime

  import Ecto.Query

  @default_importance 0.4
  @entry_type "Observation"

  @doc """
  Ingest a file for the given agent. Parses the file into chunks,
  deduplicates via content_hash, and creates memory entries.

  Options:
  - `:force` - reprocess even when the parsed document hash is unchanged

  Returns `{:ok, %{created: count, restored: count, skipped: count, archived: count, unchanged: boolean}}`.
  """
  def ingest_file(agent_id, file_path, opts \\ []) do
    filename = Path.basename(file_path)
    force? = Keyword.get(opts, :force, false)

    with :ok <- validate_ingest_path(agent_id, file_path),
         {:ok, chunks} <- Parser.parse(file_path) do
      document_hash = document_hash(chunks)
      existing = existing_hashes(agent_id, filename)

      if not force? and latest_document_hash(agent_id, filename) == document_hash and
           MapSet.size(existing) > 0 do
        record_run!(agent_id, %{
          source_file: filename,
          source_path: Path.expand(file_path),
          status: "skipped",
          chunk_count: length(chunks),
          skipped_count: length(chunks),
          metadata: %{
            "source" => "manual_or_watcher_ingest",
            "reason" => "unchanged_document",
            "document_hash" => document_hash,
            "content_hashes" => Enum.map(chunks, & &1.metadata["content_hash"]),
            "forced" => false
          }
        })

        {:ok, %{created: 0, restored: 0, skipped: length(chunks), archived: 0, unchanged: true}}
      else
        new_hashes = MapSet.new(chunks, fn c -> c.metadata["content_hash"] end)

        archived = archive_stale_entries(agent_id, filename, existing, new_hashes)

        {created, restored, skipped} =
          Enum.reduce(chunks, {0, 0, 0}, fn chunk,
                                            {created_count, restored_count, skipped_count} ->
            hash = chunk.metadata["content_hash"]

            if MapSet.member?(existing, hash) do
              {created_count, restored_count, skipped_count + 1}
            else
              case archived_entry(agent_id, filename, hash) do
                nil ->
                  attrs = memory_attrs(agent_id, file_path, document_hash, chunk)

                  case Memory.create_memory(attrs) do
                    {:ok, _entry} ->
                      {created_count + 1, restored_count, skipped_count}

                    {:error, reason} ->
                      Logger.warning(
                        "Failed to ingest chunk from #{filename}: #{inspect(reason)}"
                      )

                      {created_count, restored_count, skipped_count}
                  end

                entry ->
                  case Memory.update_memory(entry, %{
                         status: "active",
                         content: chunk.content,
                         metadata:
                           memory_metadata(file_path, document_hash, chunk)
                           |> Map.put("restored_at", DateTime.utc_now() |> DateTime.to_iso8601())
                       }) do
                    {:ok, _entry} ->
                      {created_count, restored_count + 1, skipped_count}

                    {:error, reason} ->
                      Logger.warning(
                        "Failed to restore archived ingest chunk from #{filename}: #{inspect(reason)}"
                      )

                      {created_count, restored_count, skipped_count}
                  end
              end
            end
          end)

        Logger.info(
          "Ingest complete: #{filename} → #{created} created, #{restored} restored, #{skipped} skipped, #{archived} archived"
        )

        record_run!(agent_id, %{
          source_file: filename,
          source_path: Path.expand(file_path),
          status: "imported",
          chunk_count: length(chunks),
          created_count: created,
          skipped_count: skipped,
          archived_count: archived,
          metadata: %{
            "source" => "manual_or_watcher_ingest",
            "document_hash" => document_hash,
            "content_hashes" => Enum.map(chunks, & &1.metadata["content_hash"]),
            "forced" => force?,
            "restored_count" => restored
          }
        })

        {:ok,
         %{
           created: created,
           restored: restored,
           skipped: skipped,
           archived: archived,
           unchanged: false
         }}
      end
    else
      {:error, :ingest_path_not_allowed} ->
        allowed_roots =
          case Runtime.authorize_ingest_path(
                 agent_id,
                 Runtime.get_agent!(agent_id).workspace_root,
                 file_path
               ) do
            {:error, {:ingest_path_not_allowed, roots}} -> roots
            _ -> []
          end

        record_run!(agent_id, %{
          source_file: filename,
          source_path: Path.expand(file_path),
          status: "failed",
          metadata: %{
            "reason" => "ingest_path_not_allowed",
            "allowed_roots" => allowed_roots
          }
        })

        {:error, :ingest_path_not_allowed}

      {:error, reason} ->
        Logger.warning("Failed to parse #{file_path}: #{inspect(reason)}")

        record_run!(agent_id, %{
          source_file: filename,
          source_path: Path.expand(file_path),
          status: "failed",
          metadata: %{"reason" => inspect(reason)}
        })

        {:error, reason}
    end
  end

  @doc """
  Archive all memory entries for a deleted ingest file.
  """
  def archive_file(agent_id, filename) do
    count = archive_all_entries(agent_id, filename)
    Logger.info("Archived #{count} entries for deleted file: #{filename}")

    record_run!(agent_id, %{
      source_file: filename,
      source_path: nil,
      status: "archived",
      archived_count: count,
      metadata: %{"source" => "archive_file"}
    })

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
      {fragment("json_extract(?, '$.source_file')", e.metadata), count(e.id)}
    )
    |> group_by([e], fragment("json_extract(?, '$.source_file')", e.metadata))
    |> HydraX.Repo.all()
    |> Enum.map(fn {file, count} -> %{file: file, entries: count} end)
  end

  def list_ingest_runs(agent_id, limit \\ 20) do
    Run
    |> where([run], run.agent_id == ^agent_id)
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> HydraX.Repo.all()
  end

  # -- Private helpers --

  defp latest_document_hash(agent_id, filename) do
    Run
    |> where([run], run.agent_id == ^agent_id and run.source_file == ^filename)
    |> where([run], run.status in ["imported", "skipped"])
    |> order_by([run], desc: run.inserted_at)
    |> limit(1)
    |> HydraX.Repo.one()
    |> case do
      nil -> nil
      run -> get_in(run.metadata || %{}, ["document_hash"])
    end
  end

  defp record_run!(agent_id, attrs) do
    %Run{}
    |> Run.changeset(Map.put(attrs, :agent_id, agent_id))
    |> HydraX.Repo.insert!()
  end

  defp document_hash(chunks) do
    chunks
    |> Enum.map(& &1.metadata["content_hash"])
    |> Enum.join(":")
    |> Parser.content_hash()
  end

  defp existing_hashes(agent_id, filename) do
    HydraX.Memory.Entry
    |> where([e], e.agent_id == ^agent_id and e.status == "active")
    |> where([e], fragment("json_extract(?, '$.source')", e.metadata) == "ingest")
    |> where([e], fragment("json_extract(?, '$.source_file')", e.metadata) == ^filename)
    |> select([e], fragment("json_extract(?, '$.content_hash')", e.metadata))
    |> HydraX.Repo.all()
    |> MapSet.new()
  end

  defp archived_entry(agent_id, filename, hash) do
    HydraX.Memory.Entry
    |> where([e], e.agent_id == ^agent_id and e.status == "archived")
    |> where([e], fragment("json_extract(?, '$.source')", e.metadata) == "ingest")
    |> where([e], fragment("json_extract(?, '$.source_file')", e.metadata) == ^filename)
    |> where([e], fragment("json_extract(?, '$.content_hash')", e.metadata) == ^hash)
    |> order_by([e], desc: e.updated_at)
    |> limit(1)
    |> HydraX.Repo.one()
  end

  defp memory_attrs(agent_id, file_path, document_hash, chunk) do
    %{
      agent_id: agent_id,
      type: @entry_type,
      status: "candidate",
      content: chunk.content,
      importance: @default_importance,
      metadata: memory_metadata(file_path, document_hash, chunk)
    }
  end

  defp memory_metadata(file_path, document_hash, chunk) do
    Map.merge(chunk.metadata, %{
      "source" => "ingest",
      "ingested_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "document_hash" => document_hash,
      "source_path" => Path.expand(file_path),
      "approval_state" => "provisional",
      "lifecycle_scope" => "ingest"
    })
  end

  defp validate_ingest_path(agent_id, file_path) do
    agent = Runtime.get_agent!(agent_id)

    case Runtime.authorize_ingest_path(agent_id, agent.workspace_root, file_path) do
      :ok -> :ok
      {:error, {:ingest_path_not_allowed, _roots}} -> {:error, :ingest_path_not_allowed}
    end
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
