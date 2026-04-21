defmodule HydraX.Product.Requirement do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Product.Scope

  @statuses ~w(draft accepted rejected)

  schema "requirements" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :grounded, :boolean, default: false
    field :metadata, :map, default: %{}

    field :scope, :string, default: "project"
    field :scope_root_id, :integer

    belongs_to :project, HydraX.Product.Project
    has_many :requirement_insights, HydraX.Product.RequirementInsight

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(requirement, attrs) do
    requirement
    |> cast(attrs, [:project_id, :title, :body, :status, :grounded, :metadata, :scope, :scope_root_id])
    |> validate_required([:project_id, :title, :body, :status, :grounded])
    |> validate_inclusion(:status, @statuses)
    |> Scope.validate_and_default()
    |> foreign_key_constraint(:project_id)
  end
end
