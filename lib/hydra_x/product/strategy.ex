defmodule HydraX.Product.Strategy do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft active superseded archived)

  schema "strategies" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [:project_id, :title, :body, :status, :metadata])
    |> validate_required([:project_id, :title, :body, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
