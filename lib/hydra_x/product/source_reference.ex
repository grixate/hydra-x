defmodule HydraX.Product.SourceReference do
  @moduledoc """
  Polymorphic reference between a graph node and a Library source.

  Per Source-as-Data spec §5, these are **data**, not graph edges. They live
  on the node (conceptually) but are stored in a dedicated table so they can
  be queried efficiently in both directions:

    * "What sources support this Insight?" → by `{node_type, node_id}`
    * "Which nodes reference this source?" → by `source_id`
    * "Which sources do Decisions cite?" → by `project_id` + `node_type`

  References do **not** generate graph edges and are invisible to ELK layout.
  They surface in Node Detail (§6) and the Library Referenced-by view.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @relationships ~w(extracted_from supports cites contradicts)
  @confidences ~w(high medium low)
  @creators ~w(agent user system)

  schema "source_references" do
    field :node_type, :string
    field :node_id, :integer
    field :relationship, :string, default: "cites"
    field :excerpt, :string
    field :confidence, :string
    field :page_or_position, :string
    field :created_by, :string, default: "agent"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    belongs_to :source, HydraX.Product.Source

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def relationships, do: @relationships
  def confidences, do: @confidences

  def changeset(reference, attrs) do
    reference
    |> cast(attrs, [
      :project_id,
      :source_id,
      :node_type,
      :node_id,
      :relationship,
      :excerpt,
      :confidence,
      :page_or_position,
      :created_by,
      :metadata
    ])
    |> validate_required([:project_id, :source_id, :node_type, :node_id, :relationship])
    |> validate_inclusion(:relationship, @relationships)
    |> validate_inclusion(:confidence, @confidences, message: "must be high/medium/low or nil")
    |> validate_inclusion(:created_by, @creators)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:source_id)
    |> unique_constraint([:source_id, :node_type, :node_id, :relationship],
      name: :source_refs_source_node_rel_idx,
      message: "reference already exists"
    )
  end
end
