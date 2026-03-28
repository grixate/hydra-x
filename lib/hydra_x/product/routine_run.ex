defmodule HydraX.Product.RoutineRun do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(running success partial failed)

  schema "routine_runs" do
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :status, :string, default: "running"
    field :prompt_resolved, :string
    field :output, :string
    field :token_count, :integer
    field :cost_cents, :integer
    field :metadata, :map, default: %{}

    belongs_to :routine, HydraX.Product.Routine

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :routine_id, :started_at, :completed_at, :status,
      :prompt_resolved, :output, :token_count, :cost_cents, :metadata
    ])
    |> validate_required([:routine_id, :started_at, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:routine_id)
  end
end
