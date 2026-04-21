defmodule HydraX.Coherence.Contradiction do
  @moduledoc """
  A detected contradiction between two graph nodes.

  Modes (`coherence-spec.md` §3):
    * `in_project`              — two project-scope nodes
    * `cross_project`           — two project-scope nodes in different projects
    * `principle_vs_practice`   — shared-memory node vs. project-scope node
    * `intra_shared_memory`     — two shared-memory nodes
  """

  use Ecto.Schema
  import Ecto.Changeset

  @modes ~w(in_project cross_project principle_vs_practice intra_shared_memory)
  @severities ~w(low medium high)
  @statuses ~w(open under_review resolved dismissed stale acknowledged_tension)
  @confidences ~w(low medium high)
  @node_scopes ~w(project shared)

  schema "contradictions" do
    field :mode, :string

    field :node_a_type, :string
    field :node_a_id, :integer
    field :node_a_scope, :string, default: "project"

    field :node_b_type, :string
    field :node_b_id, :integer
    field :node_b_scope, :string, default: "project"

    field :explanation, :string
    field :severity, :string, default: "medium"
    field :severity_reason, :string
    field :confidence, :string, default: "medium"

    field :context_diff, :map
    field :suggested_resolutions, {:array, :map}, default: []

    field :status, :string, default: "open"
    field :status_reason, :string

    field :resolved_at, :utc_datetime_usec
    field :detected_at, :utc_datetime_usec
    field :last_confirmed_at, :utc_datetime_usec
    field :dismissed_count, :integer, default: 0

    belongs_to :project, HydraX.Product.Project

    belongs_to :shared_scope, HydraX.Accounts.SharedScope,
      foreign_key: :shared_scope_id,
      type: :binary_id

    belongs_to :resolved_by, HydraX.Accounts.User,
      foreign_key: :resolved_by_user_id,
      type: :binary_id

    has_many :events, HydraX.Coherence.ContradictionEvent,
      foreign_key: :contradiction_id

    timestamps(type: :utc_datetime_usec)
  end

  def modes, do: @modes
  def severities, do: @severities
  def statuses, do: @statuses
  def confidences, do: @confidences

  def changeset(contradiction, attrs) do
    contradiction
    |> cast(attrs, [
      :project_id,
      :shared_scope_id,
      :mode,
      :node_a_type,
      :node_a_id,
      :node_a_scope,
      :node_b_type,
      :node_b_id,
      :node_b_scope,
      :explanation,
      :severity,
      :severity_reason,
      :confidence,
      :context_diff,
      :suggested_resolutions,
      :status,
      :status_reason,
      :resolved_by_user_id,
      :resolved_at,
      :detected_at,
      :last_confirmed_at,
      :dismissed_count
    ])
    |> validate_required([
      :mode,
      :node_a_type,
      :node_a_id,
      :node_b_type,
      :node_b_id,
      :severity,
      :confidence,
      :status,
      :detected_at,
      :last_confirmed_at
    ])
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:confidence, @confidences)
    |> validate_inclusion(:node_a_scope, @node_scopes)
    |> validate_inclusion(:node_b_scope, @node_scopes)
    |> unique_constraint(
      [:mode, :node_a_type, :node_a_id, :node_b_type, :node_b_id],
      name: :contradictions_unique_pair_index
    )
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:shared_scope_id)
  end
end
