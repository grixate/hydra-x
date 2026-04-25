defmodule HydraXWeb.AgentStatusAPIController do
  use HydraXWeb, :controller

  import Ecto.Query

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Product.AgentTasks
  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Repo

  action_fallback HydraXWeb.ProjectAPIFallbackController

  # Conversational personas (5) — have AgentProfile bindings on Project
  @conversational_personas ~w(researcher strategist architect designer memory_agent)

  # Background virtual agents (2) — Zone 1 per Command Center spec §3
  @background_agents ~w(coherence continuous_research)

  @all_agents @conversational_personas ++ @background_agents

  def index(conn, %{"project_id" => project_id}) do
    project_id = parse_int(project_id)

    strip = AgentTasks.agent_strip(project_id, @all_agents) |> Map.new(&{&1.agent_id, &1})

    statuses =
      Enum.map(@all_agents, fn agent_id ->
        entry = Map.get(strip, agent_id, %{state: "idle", active_count: 0, summary: nil})
        ready_count = draft_count_for_persona(project_id, agent_id)
        last_active = last_active_at(project_id, agent_id)

        %{
          persona: agent_id,
          state: entry.state,
          summary: entry.summary,
          active_count: entry.active_count,
          working_detail: entry.summary,
          ready_count: ready_count,
          last_active_at: last_active
        }
      end)

    json(conn, %{data: statuses})
  end

  defp draft_count_for_persona(project_id, persona) do
    case persona do
      "researcher" ->
        GraphNode
        |> where(
          [i],
          i.project_id == ^project_id and i.type_key == "insight" and i.status == "draft"
        )
        |> Repo.aggregate(:count, :id)

      "strategist" ->
        decisions =
          GraphNode
          |> where(
            [d],
            d.project_id == ^project_id and d.type_key == "decision" and d.status == "draft"
          )
          |> Repo.aggregate(:count, :id)

        requirements =
          GraphNode
          |> where(
            [r],
            r.project_id == ^project_id and r.type_key == "requirement" and r.status == "draft"
          )
          |> Repo.aggregate(:count, :id)

        decisions + requirements

      _ ->
        0
    end
  end

  defp last_active_at(project_id, persona) when persona in @conversational_personas do
    ProductConversation
    |> where([c], c.project_id == ^project_id and c.persona == ^persona)
    |> join(:left, [c], m in ProductMessage, on: m.product_conversation_id == c.id)
    |> select([_c, m], max(m.inserted_at))
    |> Repo.one()
  end

  defp last_active_at(_project_id, _persona), do: nil

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
