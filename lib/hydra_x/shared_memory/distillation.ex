defmodule HydraX.SharedMemory.Distillation do
  @moduledoc """
  A link from a shared memory node back to the project-level episode
  that supported its creation. Spec §4.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "distillations" do
    field :episode_node_type, :string
    field :episode_node_id, :integer
    field :weight, :float, default: 1.0
    field :context_snippet, :string

    belongs_to :shared_node, HydraX.SharedMemory.Node, foreign_key: :shared_node_id
    belongs_to :episode_project, HydraX.Product.Project, foreign_key: :episode_project_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(distillation, attrs) do
    distillation
    |> cast(attrs, [
      :shared_node_id,
      :episode_project_id,
      :episode_node_type,
      :episode_node_id,
      :weight,
      :context_snippet
    ])
    |> validate_required([:shared_node_id, :episode_node_type, :episode_node_id])
    |> validate_number(:weight, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint([:shared_node_id, :episode_node_type, :episode_node_id],
      name: :distillations_unique_link_index
    )
    |> foreign_key_constraint(:shared_node_id)
    |> foreign_key_constraint(:episode_project_id)
  end
end
