defmodule HydraX.Product.GraphEdge do
  use Ecto.Schema
  import Ecto.Changeset

  @node_types ~w(signal insight decision strategy requirement design_node architecture_node task learning simulation)
  @kinds ~w(lineage dependency supports contradicts supersedes blocks enables)

  schema "product_graph_edges" do
    field :from_node_type, :string
    field :from_node_id, :integer
    field :to_node_type, :string
    field :to_node_id, :integer
    field :kind, :string
    field :weight, :float, default: 1.0
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def node_types, do: @node_types
  def kinds, do: @kinds

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [
      :project_id,
      :from_node_type,
      :from_node_id,
      :to_node_type,
      :to_node_id,
      :kind,
      :weight,
      :metadata
    ])
    |> validate_required([
      :project_id,
      :from_node_type,
      :from_node_id,
      :to_node_type,
      :to_node_id,
      :kind
    ])
    |> validate_inclusion(:from_node_type, @node_types)
    |> validate_inclusion(:to_node_type, @node_types)
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:weight, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:from_node_type, :from_node_id, :to_node_type, :to_node_id, :kind])
  end
end
