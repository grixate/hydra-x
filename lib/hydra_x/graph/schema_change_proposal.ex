defmodule HydraX.Graph.SchemaChangeProposal do
  @moduledoc """
  A proposed change to a domain's schema, authored by an operator or
  agent. Approved proposals are applied atomically by the registry and
  trigger a PubSub schema-version bump.

  V1 supports only additive changes (§8.3 of the substrate spec):
  removing or renaming types, changing attribute types, or deleting
  statuses is deferred to V2.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Domain

  @change_kinds ~w(
    add_node_type
    add_relationship_type
    add_flag_type
    extend_node_type
    add_attribute
    modify_attribute_schema
  )

  @statuses ~w(pending approved rejected superseded)

  schema "schema_change_proposals" do
    field :proposed_by_agent_id, :string
    field :proposed_by_operator, :boolean, default: false
    field :change_kind, :string
    field :payload, :map, default: %{}
    field :rationale, :string
    field :status, :string, default: "pending"
    field :reviewed_by_operator, :boolean, default: false
    field :applied_at, :utc_datetime_usec

    belongs_to :domain, Domain

    timestamps(type: :utc_datetime_usec)
  end

  def change_kinds, do: @change_kinds
  def statuses, do: @statuses

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :domain_id,
      :proposed_by_agent_id,
      :proposed_by_operator,
      :change_kind,
      :payload,
      :rationale,
      :status,
      :reviewed_by_operator,
      :applied_at
    ])
    |> validate_required([:domain_id, :change_kind, :status, :payload])
    |> validate_inclusion(:change_kind, @change_kinds)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:domain_id)
  end
end
