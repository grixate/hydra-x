defmodule HydraX.SharedMemory.Node do
  @moduledoc """
  A node in the user's shared ("You") scope.

  Six typed varieties per `shared-memory-spec.md` §3:
    * `principle` — generalised truths the user has internalised
    * `heuristic` — rules of thumb learned from outcomes
    * `method` — repeatable approaches that work for the user
    * `mental_model` — frameworks the user reasons through
    * `identity_fact` — stable facts about background / expertise / role
    * `value` — aesthetic and ethical commitments
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active archived superseded)
  @types ~w(principle heuristic method mental_model identity_fact value)

  schema "shared_memory_nodes" do
    field :node_type, :string
    field :title, :string
    field :body, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}
    field :last_referenced_at, :utc_datetime_usec

    belongs_to :shared_scope, HydraX.Accounts.SharedScope,
      foreign_key: :shared_scope_id,
      type: :binary_id

    has_many :distillations, HydraX.SharedMemory.Distillation, foreign_key: :shared_node_id

    timestamps(type: :utc_datetime_usec)
  end

  def node_types, do: @types
  def statuses, do: @statuses

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :shared_scope_id,
      :node_type,
      :title,
      :body,
      :status,
      :metadata,
      :last_referenced_at
    ])
    |> validate_required([:shared_scope_id, :node_type, :title, :status])
    |> validate_inclusion(:node_type, @types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:shared_scope_id)
  end
end
