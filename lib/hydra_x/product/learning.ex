defmodule HydraX.Product.Learning do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Product.Scope

  @statuses ~w(draft active archived)
  @learning_types ~w(retrospective post_mortem usage_data experiment_result)

  schema "learnings" do
    field :title, :string
    field :body, :string
    field :learning_type, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    field :scope, :string, default: "project"
    field :scope_root_id, :integer

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(learning, attrs) do
    learning
    |> cast(attrs, [:project_id, :title, :body, :learning_type, :status, :metadata, :scope, :scope_root_id])
    |> validate_required([:project_id, :title, :body, :learning_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:learning_type, @learning_types)
    |> Scope.validate_and_default()
    |> foreign_key_constraint(:project_id)
  end
end
