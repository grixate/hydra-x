defmodule HydraX.Product.BoardSession do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active completed archived)

  schema "board_sessions" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "active"
    field :created_by_user_id, :string
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    has_many :board_nodes, HydraX.Product.BoardNode
    has_many :board_edges, HydraX.Product.BoardEdge
    has_many :product_conversations, HydraX.Product.ProductConversation

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:project_id, :title, :description, :status, :created_by_user_id, :metadata])
    |> validate_required([:project_id, :title, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
