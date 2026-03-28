defmodule HydraX.Product.Learning do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft active archived)
  @learning_types ~w(retrospective post_mortem usage_data experiment_result)

  schema "learnings" do
    field :title, :string
    field :body, :string
    field :learning_type, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(learning, attrs) do
    learning
    |> cast(attrs, [:project_id, :title, :body, :learning_type, :status, :metadata])
    |> validate_required([:project_id, :title, :body, :learning_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:learning_type, @learning_types)
    |> foreign_key_constraint(:project_id)
  end
end
