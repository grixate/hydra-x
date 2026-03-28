defmodule HydraX.Product.TaskFeedback do
  use Ecto.Schema
  import Ecto.Changeset

  @ratings ~w(good needs_improvement poor)

  schema "task_feedback" do
    field :rating, :string
    field :comment, :string
    field :feedback_tags, {:array, :string}, default: []
    field :created_by, :string, default: "human"
    field :metadata, :map, default: %{}

    belongs_to :task, HydraX.Product.Task

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [:task_id, :rating, :comment, :feedback_tags, :created_by, :metadata])
    |> validate_required([:task_id, :rating])
    |> validate_inclusion(:rating, @ratings)
    |> foreign_key_constraint(:task_id)
  end
end
