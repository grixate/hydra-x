defmodule HydraX.Product.GraphFlag do
  use Ecto.Schema
  import Ecto.Changeset

  @flag_types ~w(needs_review contradicted stale orphaned confidence_decayed)
  @statuses ~w(open acknowledged resolved)

  schema "graph_flags" do
    field :node_type, :string
    field :node_id, :integer
    field :flag_type, :string
    field :reason, :string
    field :source_agent, :string
    field :status, :string, default: "open"
    field :resolved_by, :string
    field :resolved_at, :utc_datetime

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(flag, attrs) do
    flag
    |> cast(attrs, [
      :project_id,
      :node_type,
      :node_id,
      :flag_type,
      :reason,
      :source_agent,
      :status,
      :resolved_by,
      :resolved_at
    ])
    |> validate_required([:project_id, :node_type, :node_id, :flag_type, :status])
    |> validate_inclusion(:flag_type, @flag_types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
