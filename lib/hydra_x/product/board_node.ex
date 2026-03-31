defmodule HydraX.Product.BoardNode do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft promoted discarded)
  @node_types ~w(insight decision strategy requirement design_node architecture_node task learning source_ref)

  schema "board_nodes" do
    field :node_type, :string
    field :title, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :promoted_node_type, :string
    field :promoted_node_id, :integer
    field :created_by, :string, default: "agent"
    field :metadata, :map, default: %{}

    belongs_to :board_session, HydraX.Product.BoardSession
    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses
  def node_types, do: @node_types

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :board_session_id,
      :project_id,
      :node_type,
      :title,
      :body,
      :status,
      :promoted_node_type,
      :promoted_node_id,
      :created_by,
      :metadata
    ])
    |> validate_required([:board_session_id, :project_id, :node_type, :title, :body, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:node_type, @node_types)
    |> foreign_key_constraint(:board_session_id)
    |> foreign_key_constraint(:project_id)
  end
end
