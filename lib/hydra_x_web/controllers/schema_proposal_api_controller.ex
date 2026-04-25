defmodule HydraXWeb.SchemaProposalAPIController do
  @moduledoc """
  HTTP surface for the schema-change proposal flow (spec §8).

    * `GET    /api/v1/domains/:slug/proposals[?status=pending]`
    * `POST   /api/v1/domains/:slug/proposals`
    * `PATCH  /api/v1/domains/:slug/proposals/:id` with
      `{ "action": "approve" | "reject" }`
  """

  use HydraXWeb, :controller

  alias HydraX.Graph.Domains
  alias HydraX.Graph.Proposals

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def index(conn, %{"domain_slug" => slug} = params) do
    with {:ok, domain} <- fetch_domain(slug) do
      proposals =
        Proposals.list_proposals(domain.id, status: params["status"])
        |> Enum.map(&serialize/1)

      json(conn, %{data: proposals})
    end
  end

  def create(conn, %{"domain_slug" => slug, "proposal" => params}) do
    with {:ok, domain} <- fetch_domain(slug),
         {:ok, proposal} <-
           Proposals.propose(
             domain,
             params["change_kind"],
             params["payload"] || %{},
             Map.take(params, [
               "rationale",
               "proposed_by_agent_id",
               "proposed_by_operator"
             ])
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize(proposal)})
    end
  end

  def update(conn, %{"id" => id, "action" => action} = params) do
    proposal = Proposals.get_proposal!(id)
    by_operator = Map.get(params, "by_operator", true)

    result =
      case action do
        "approve" -> Proposals.approve(proposal, by_operator: by_operator)
        "reject" -> Proposals.reject(proposal, by_operator: by_operator)
        _ -> {:error, :unknown_action}
      end

    case result do
      {:ok, updated} ->
        json(conn, %{data: serialize(updated)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp fetch_domain(slug) do
    case Domains.get_domain_by_slug(slug) do
      nil -> {:error, :not_found}
      domain -> {:ok, domain}
    end
  end

  defp serialize(p) do
    %{
      id: p.id,
      domain_id: p.domain_id,
      change_kind: p.change_kind,
      payload: p.payload || %{},
      rationale: p.rationale,
      status: p.status,
      proposed_by_agent_id: p.proposed_by_agent_id,
      proposed_by_operator: p.proposed_by_operator,
      reviewed_by_operator: p.reviewed_by_operator,
      applied_at: p.applied_at,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end
end
