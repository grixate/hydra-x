defmodule HydraX.Product.Decision do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft active superseded archived)
  @fields ~w(project_id title body status decided_by decided_at alternatives_considered metadata)a

  schema "decisions" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "active"
    field :decided_by, :string
    field :decided_at, :utc_datetime
    field :alternatives_considered, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, @fields)
    |> validate_required([:project_id, :title, :body, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
