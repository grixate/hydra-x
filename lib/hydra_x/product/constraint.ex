defmodule HydraX.Product.Constraint do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active suspended archived)
  @scopes ~w(global technical design process business)
  @enforcements ~w(strict advisory)

  schema "constraints" do
    field :title, :string
    field :body, :string
    field :scope, :string, default: "global"
    field :enforcement, :string, default: "strict"
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(constraint, attrs) do
    constraint
    |> cast(attrs, [:project_id, :title, :body, :scope, :enforcement, :status, :metadata])
    |> validate_required([:project_id, :title, :body, :scope, :enforcement, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:enforcement, @enforcements)
    |> foreign_key_constraint(:project_id)
  end
end
