defmodule HydraX.Product.BoardEdge do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(lineage dependency supports contradicts supersedes blocks enables constrains)

  schema "board_edges" do
    field :kind, :string
    field :metadata, :map, default: %{}

    belongs_to :board_session, HydraX.Product.BoardSession
    belongs_to :from_board_node, HydraX.Product.BoardNode
    belongs_to :to_board_node, HydraX.Product.BoardNode

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:board_session_id, :from_board_node_id, :to_board_node_id, :kind, :metadata])
    |> validate_required([:board_session_id, :from_board_node_id, :to_board_node_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:board_session_id)
    |> foreign_key_constraint(:from_board_node_id)
    |> foreign_key_constraint(:to_board_node_id)
    |> unique_constraint([:from_board_node_id, :to_board_node_id, :kind])
  end
end
