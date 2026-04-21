defmodule HydraX.Product.DesignNode do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Product.Scope

  @statuses ~w(draft active superseded archived)
  @node_types ~w(user_flow wireframe interaction_pattern component_spec design_rationale)

  schema "design_nodes" do
    field :title, :string
    field :body, :string
    field :node_type, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    field :scope, :string, default: "project"
    field :scope_root_id, :integer

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(design_node, attrs) do
    design_node
    |> cast(attrs, [:project_id, :title, :body, :node_type, :status, :metadata, :scope, :scope_root_id])
    |> validate_required([:project_id, :title, :body, :node_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:node_type, @node_types)
    |> Scope.validate_and_default()
    |> foreign_key_constraint(:project_id)
  end
end
