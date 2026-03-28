defmodule HydraX.Product.ArchitectureNode do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft active superseded archived)
  @node_types ~w(system_design data_model api_contract infra_choice tech_selection)

  schema "architecture_nodes" do
    field :title, :string
    field :body, :string
    field :node_type, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(architecture_node, attrs) do
    architecture_node
    |> cast(attrs, [:project_id, :title, :body, :node_type, :status, :metadata])
    |> validate_required([:project_id, :title, :body, :node_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:node_type, @node_types)
    |> foreign_key_constraint(:project_id)
  end
end
