defmodule HydraXWeb.LibraryAPIController do
  @moduledoc """
  Source-as-Data Library API — spec §4 + §6.

  All endpoints are project-scoped. Shape mirrors the conceptual capabilities
  in spec §4 so agents and the UI share one surface.
  """

  use HydraXWeb, :controller

  alias HydraX.Product.Library
  alias HydraX.Graph.Node, as: GraphNode
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  # ---- search / browse -----------------------------------------------

  def search(conn, %{"project_id" => project_id} = params) do
    query = params["q"] || params["query"] || ""

    limit =
      case params["limit"] do
        nil -> 10
        v when is_binary(v) -> String.to_integer(v)
        v when is_integer(v) -> v
      end

    results =
      Library.search(project_id, query,
        limit: limit,
        include_archived: params["include_archived"] == "true"
      )

    payload =
      Enum.map(results, fn %{source: s, score: score, top_chunk: chunk} ->
        s
        |> ProductPayload.source_json(false)
        |> Map.put(:score, score)
        |> Map.put(:top_chunk, chunk)
        |> Map.put(:promoted_to_graph, s.promoted_to_graph)
        |> Map.put(:archived_at, s.archived_at)
      end)

    json(conn, %{data: payload})
  end

  def recent(conn, %{"project_id" => project_id} = params) do
    limit =
      case params["limit"] do
        nil -> 25
        v when is_binary(v) -> String.to_integer(v)
        v when is_integer(v) -> v
      end

    data =
      project_id
      |> Library.list_recent(limit: limit)
      |> Enum.map(&source_payload/1)

    json(conn, %{data: data})
  end

  def unprocessed(conn, %{"project_id" => project_id}) do
    data =
      project_id
      |> Library.unprocessed()
      |> Enum.map(&source_payload/1)

    json(conn, %{data: data})
  end

  def by_bucket(conn, %{"project_id" => project_id, "bucket" => bucket}) do
    with :ok <- valid_bucket(bucket) do
      data =
        project_id
        |> Library.list_by_bucket(bucket)
        |> Enum.map(&source_payload/1)

      json(conn, %{data: data, bucket: bucket})
    else
      {:error, :invalid_bucket} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid bucket"})
    end
  end

  def candidates(conn, %{"project_id" => project_id} = params) do
    threshold =
      case params["threshold"] do
        nil -> 5
        v when is_binary(v) -> String.to_integer(v)
        v when is_integer(v) -> v
      end

    data =
      project_id
      |> Library.promotion_candidates(threshold: threshold)
      |> Enum.map(fn %{source: s, reference_count: c} ->
        s
        |> source_payload()
        |> Map.put(:reference_count, c)
      end)

    json(conn, %{data: data, threshold: threshold})
  end

  # ---- single source -------------------------------------------------

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, source} <- Library.get(project_id, id) do
      summary = Library.reference_summary(project_id, source.id)

      payload =
        source
        |> source_payload()
        |> Map.put(:referenced_by, summary)

      json(conn, %{data: payload})
    end
  end

  def content(conn, %{"project_id" => project_id, "id" => id} = params) do
    max = params["max_chars"] |> maybe_int()

    with {:ok, content} <- Library.get_content(project_id, id, max_chars: max) do
      json(conn, %{data: %{content: content}})
    end
  end

  def referenced_by(conn, %{"project_id" => project_id, "id" => id}) do
    summary = Library.reference_summary(project_id, id)
    json(conn, %{data: summary})
  end

  # ---- promotion / demotion / archive --------------------------------

  def promote(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, source} <- Library.get(project_id, id),
         {:ok, updated} <- Library.promote(source) do
      json(conn, %{data: source_payload(updated)})
    end
  end

  def demote(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, source} <- Library.get(project_id, id),
         {:ok, updated} <- Library.demote(source) do
      json(conn, %{data: source_payload(updated)})
    end
  end

  def archive(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, source} <- Library.get(project_id, id),
         {:ok, updated} <- Library.archive(source) do
      json(conn, %{data: source_payload(updated)})
    end
  end

  def unarchive(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, source} <- Library.get(project_id, id),
         {:ok, updated} <- Library.unarchive(source) do
      json(conn, %{data: source_payload(updated)})
    end
  end

  @doc """
  Library spec §10 — extract a passage from a source as a first-class
  `excerpt` node and link it via `has_excerpt`. Body fields:

      passage_text       (required) — the excerpted text
      position_anchor    (optional) — page / character offset / section
      extraction_note    (optional) — annotation about why this excerpt matters
      extracted_by       (optional) — "user" (default) or "agent"
  """
  def create_excerpt(conn, %{"project_id" => project_id, "id" => id} = params) do
    project_id = parse_int(project_id)
    source_id = parse_int(id)

    passage_text = params["passage_text"] || ""
    position_anchor = params["position_anchor"] || %{}
    extraction_note = params["extraction_note"]
    extracted_by = params["extracted_by"] || "user"

    cond do
      passage_text == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "passage_text is required"})

      true ->
        with {:ok, %GraphNode{} = source} <- Library.get(project_id, source_id),
             {:ok, excerpt} <-
               HydraX.Graph.Nodes.create_node(project_id, %{
                 type_key: "excerpt",
                 title: short_title(passage_text),
                 body: passage_text,
                 status: "active",
                 attributes: %{
                   "source_id" => source.id,
                   "passage_text" => passage_text,
                   "position_anchor" => position_anchor,
                   "extracted_by" => extracted_by,
                   "extraction_note" => extraction_note
                 }
               }),
             {:ok, _edge} <-
               HydraX.Graph.Relationships.create_relationship(source, excerpt, "has_excerpt",
                 weight: 1.0
               ) do
          conn
          |> put_status(:created)
          |> json(%{
            data: %{
              id: excerpt.id,
              source_id: source.id,
              title: excerpt.title,
              passage_text: passage_text
            }
          })
        end
    end
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)

  defp short_title(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(8)
    |> Enum.join(" ")
    |> String.slice(0, 80)
  end

  # ---- source references ---------------------------------------------

  def for_node(conn, %{
        "project_id" => project_id,
        "node_type" => node_type,
        "node_id" => node_id
      }) do
    refs = Library.get_for_node(project_id, node_type, node_id)

    data =
      Enum.map(refs, fn ref ->
        %{
          id: ref.id,
          source_id: ref.source_id,
          relationship: ref.relationship,
          excerpt: ref.excerpt,
          confidence: ref.confidence,
          page_or_position: ref.page_or_position,
          created_by: ref.created_by,
          created_at: ref.inserted_at,
          source:
            case ref.source do
              %GraphNode{type_key: "source"} = s -> source_payload(s)
              _ -> nil
            end
        }
      end)

    json(conn, %{data: data})
  end

  def create_reference(conn, %{"project_id" => project_id} = params) do
    source_id = params["source_id"]
    node_type = params["node_type"]
    node_id = params["node_id"]

    if is_nil(source_id) or is_nil(node_type) or is_nil(node_id) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "source_id, node_type, node_id are required"})
    else
      attrs =
        params
        |> Map.take(["relationship", "excerpt", "confidence", "page_or_position", "metadata"])
        |> Map.put("created_by", "user")

      case Library.reference(project_id, source_id, node_type, node_id, attrs) do
        {:ok, ref} ->
          conn |> put_status(:created) |> json(%{data: %{id: ref.id}})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: errors_to_map(changeset)})
      end
    end
  end

  def delete_reference(conn, %{"project_id" => _project_id, "id" => id}) do
    case Library.unreference(id) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, :not_found} -> send_resp(conn, :not_found, "")
    end
  end

  # ---- helpers -------------------------------------------------------

  defp source_payload(%GraphNode{type_key: "source"} = s) do
    attrs = s.attributes || %{}

    s
    |> ProductPayload.source_json(false)
    |> Map.put(:promoted_to_graph, Map.get(attrs, "promoted_to_graph", false))
    |> Map.put(:promoted_at, Map.get(attrs, "promoted_at"))
    |> Map.put(:archived_at, s.archived_at)
  end

  defp maybe_int(nil), do: nil
  defp maybe_int(v) when is_integer(v), do: v

  defp maybe_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  @valid_buckets ~w(all referenced unreferenced promoted unprocessed archived)
  defp valid_bucket(b) when b in @valid_buckets, do: :ok
  defp valid_bucket(_), do: {:error, :invalid_bucket}
end
