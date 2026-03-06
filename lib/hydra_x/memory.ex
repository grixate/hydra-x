defmodule HydraX.Memory do
  @moduledoc """
  Typed graph memory storage with lexical search and markdown export.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias HydraX.Memory.{Edge, Entry, Markdown}
  alias HydraX.Repo

  def list_memories(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    limit = Keyword.get(opts, :limit, 100)

    Entry
    |> maybe_filter_agent(agent_id)
    |> order_by([entry], desc: entry.importance, desc: entry.updated_at)
    |> preload([:conversation])
    |> limit(^limit)
    |> Repo.all()
  end

  def search(agent_id, query, limit \\ 8)
  def search(_agent_id, "", limit), do: list_memories(limit: limit)
  def search(_agent_id, nil, limit), do: list_memories(limit: limit)

  def search(agent_id, query, limit) do
    sql = """
    SELECT m.*
    FROM memory_search ms
    JOIN memory_entries m ON m.id = ms.rowid
    WHERE ms.content MATCH ? AND (? IS NULL OR m.agent_id = ?)
    ORDER BY rank
    LIMIT ?
    """

    {:ok, %{rows: rows, columns: columns}} =
      SQL.query(Repo, sql, [fts_query(query), agent_id, agent_id, limit])

    rows
    |> Enum.map(&Enum.zip(columns, &1))
    |> Enum.map(&Map.new/1)
    |> Enum.map(&Repo.load(Entry, &1))
  rescue
    _ ->
      Entry
      |> maybe_filter_agent(agent_id)
      |> where([entry], like(entry.content, ^"%#{query}%"))
      |> order_by([entry], desc: entry.importance)
      |> limit(^limit)
      |> Repo.all()
  end

  def create_memory(attrs) do
    result =
      %Entry{}
      |> Entry.changeset(attrs)
      |> Repo.insert()

    with {:ok, entry} <- result do
      maybe_refresh_cortex(entry.agent_id)
      {:ok, entry}
    end
  end

  def link_memories(attrs) do
    %Edge{}
    |> Edge.changeset(attrs)
    |> Repo.insert()
  end

  def render_markdown(agent_id) do
    list_memories(agent_id: agent_id, limit: 500)
    |> Markdown.render()
  end

  def sync_markdown(%HydraX.Runtime.AgentProfile{} = agent) do
    content = render_markdown(agent.id)
    path = Path.join([agent.workspace_root, "memory", "MEMORY.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content <> "\n")
    {:ok, path}
  end

  defp maybe_filter_agent(query, nil), do: query
  defp maybe_filter_agent(query, agent_id), do: where(query, [entry], entry.agent_id == ^agent_id)

  defp maybe_refresh_cortex(nil), do: :ok

  defp maybe_refresh_cortex(agent_id) do
    if Registry.lookup(HydraX.ProcessRegistry, {:cortex, agent_id}) != [] do
      HydraX.Agent.Cortex.refresh(agent_id)
    end
  end

  defp fts_query(query) do
    query
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" OR ", &"\"#{&1}\"")
  end
end
