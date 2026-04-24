defmodule HydraX.Graph.NodeFlag do
  @moduledoc """
  A coherence/quality signal attached to a node — e.g. `orphan`,
  `contradicted`, `stale`. Replaces `graph_flags`, keyed now to
  `FlagTypeDefinition` rather than a hard-coded enum.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Node

  @severities ~w(info warning critical)

  schema "node_flags" do
    field :flag_type_key, :string
    field :severity, :string, default: "warning"
    field :detected_by_agent_id, :string
    field :detection_context, :map, default: %{}
    field :resolved_at, :utc_datetime_usec
    field :resolved_by_operator, :boolean, default: false

    belongs_to :node, Node

    timestamps(type: :utc_datetime_usec)
  end

  def severities, do: @severities

  def changeset(flag, attrs) do
    flag
    |> cast(attrs, [
      :node_id,
      :flag_type_key,
      :severity,
      :detected_by_agent_id,
      :detection_context,
      :resolved_at,
      :resolved_by_operator
    ])
    |> validate_required([:node_id, :flag_type_key, :severity])
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:node_id)
  end

  def resolve_changeset(flag, attrs) do
    flag
    |> cast(attrs, [:resolved_at, :resolved_by_operator])
    |> validate_required([:resolved_at])
  end
end
