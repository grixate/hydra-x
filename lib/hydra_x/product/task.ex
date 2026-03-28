defmodule HydraX.Product.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(backlog ready in_progress review done archived)
  @priorities ~w(critical high medium low)

  schema "tasks" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "backlog"
    field :assignee, :string
    field :effort_estimate, :string
    field :priority, :string, default: "medium"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:project_id, :title, :body, :status, :assignee, :effort_estimate, :priority, :metadata])
    |> validate_required([:project_id, :title, :body, :status, :priority])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> foreign_key_constraint(:project_id)
  end
end
