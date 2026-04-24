defmodule HydraXWeb.SourceAPIController do
  use HydraXWeb, :controller

  alias HydraX.Product
  alias HydraX.Product.Source
  alias HydraX.Product.AgentBridge
  alias HydraXWeb.ProductPayload

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"project_id" => project_id}) do
    sources =
      Product.list_sources(project_id,
        processing_status: conn.params["processing_status"],
        source_type: conn.params["source_type"],
        search: conn.params["search"]
      )
      |> Enum.map(&ProductPayload.source_json(&1, false))

    json(conn, %{data: sources})
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    source =
      project_id
      |> Product.get_project_source!(parse_integer(id))
      |> ProductPayload.source_json(true)

    json(conn, %{data: source})
  end

  def create(conn, %{"project_id" => project_id, "source" => params}) do
    with {:ok, %Source{} = source} <- Product.create_source(project_id, params) do
      # Stream A1.3 — auto-trigger Researcher analysis. Spawns an
      # AgentTask (visible in CC) and runs the LLM in background.
      _ = HydraX.Product.ResearcherAutoProcess.maybe_enqueue(source)

      # Source-as-Data (spec §9): honour per-project opt-in for legacy
      # source-as-node behaviour.
      source = maybe_auto_promote(source)

      conn
      |> put_status(:created)
      |> json(%{data: ProductPayload.source_json(source, true)})
    end
  end

  defp maybe_auto_promote(%Source{} = source) do
    project = Product.get_project!(source.project_id)
    meta = project.metadata || %{}

    if truthy?(Map.get(meta, "auto_promote_sources")) do
      case HydraX.Product.Library.promote(source) do
        {:ok, promoted} -> promoted
        _ -> source
      end
    else
      source
    end
  rescue
    _ -> source
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false

  def analyze(conn, %{"project_id" => project_id, "id" => id} = params) do
    project_id = parse_integer(project_id)
    source = Product.get_project_source!(project_id, parse_integer(id))
    board_session_id = params["board_session_id"]

    prompt = """
    Analyze this source document and extract key insights.

    Title: #{source.title}
    Type: #{source.source_type}

    Content (first 3000 chars):
    #{String.slice(source.content || "", 0, 3000)}

    Create insights for any significant findings. Each insight should have:
    - A clear, specific title
    - A body explaining the finding with evidence
    - A confidence level (high/medium/low)

    Connect each insight to this source via lineage.
    """

    metadata = %{
      "channel" => "source_processing",
      "external_ref" => "source_analysis_#{source.id}",
      "title" => "Analyzing: #{source.title}",
      "metadata" => %{
        "source_id" => source.id,
        "board_session_id" => board_session_id
      }
    }

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project_id, "researcher", metadata)

    Task.start(fn ->
      AgentBridge.submit_message(conversation, prompt, %{
        "source_id" => source.id,
        "board_session_id" => board_session_id,
        "auto_processing" => true
      })
    end)

    json(conn, %{data: %{conversation_id: conversation.id, source_id: source.id}})
  end

  @doc """
  B4.7 — kick off analysis for every source not yet `completed`. Typically
  invoked from the library header "Process all pending" action after a
  bulk import so the user doesn't click Re-analyze per source.
  """
  def process_pending(conn, %{"project_id" => project_id}) do
    import Ecto.Query

    project_id = parse_integer(project_id)

    # Filter + cap at the DB level — projects with thousands of sources
    # should not materialise them all just to throw most away. 25 per
    # click lets the user drain the queue without saturating the LLM
    # pool in one shot.
    pending =
      HydraX.Product.Source
      |> where([s], s.project_id == ^project_id and s.processing_status != "completed")
      |> order_by([s], asc: s.inserted_at)
      |> limit(25)
      |> HydraX.Repo.all()

    triggered =
      Enum.reduce(pending, 0, fn source, acc ->
        case HydraX.Product.ResearcherAutoProcess.enqueue(source) do
          {:ok, _task} -> acc + 1
          _ -> acc
        end
      end)

    json(conn, %{data: %{triggered: triggered, total_pending: length(pending)}})
  end

  def bulk_create(conn, %{"project_id" => project_id} = params) do
    project_id = parse_integer(project_id)
    source_params = Map.get(params, "source", %{})
    files = Map.get(source_params, "files", [])
    files = if is_list(files), do: files, else: [files]
    files = Enum.filter(files, &is_map/1)

    results =
      Enum.map(files, fn file ->
        attrs = %{
          "title" => file.filename,
          "upload" => file
        }

        case Product.create_source(project_id, attrs) do
          {:ok, source} -> {:ok, source}
          {:error, reason} -> {:error, file.filename, reason}
        end
      end)

    sources =
      results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, s} -> ProductPayload.source_json(s, false) end)

    errors =
      results
      |> Enum.filter(&match?({:error, _, _}, &1))
      |> Enum.map(fn {:error, name, _} -> name end)

    conn
    |> put_status(:created)
    |> json(%{data: %{sources: sources, errors: errors}})
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    source = Product.get_project_source!(project_id, parse_integer(id))

    with {:ok, %Source{}} <- Product.delete_source(source) do
      send_resp(conn, :no_content, "")
    end
  end

  defp parse_integer(value) do
    value
    |> to_string()
    |> String.to_integer()
  end
end
