defmodule HydraX.Product.Strategy do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Product.Scope

  @statuses ~w(draft active superseded archived)

  schema "strategies" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    field :scope, :string, default: "project"
    field :scope_root_id, :integer

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [:project_id, :title, :body, :status, :metadata, :scope, :scope_root_id])
    |> validate_required([:project_id, :title, :body, :status])
    |> validate_inclusion(:status, @statuses)
    |> Scope.validate_and_default()
    |> foreign_key_constraint(:project_id)
  end
end
