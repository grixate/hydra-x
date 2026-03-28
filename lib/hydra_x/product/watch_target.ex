defmodule HydraX.Product.WatchTarget do
  use Ecto.Schema
  import Ecto.Changeset

  @target_types ~w(competitor keyword url feed)
  @statuses ~w(active paused)

  schema "watch_targets" do
    field :target_type, :string
    field :value, :string
    field :check_interval_hours, :integer, default: 24
    field :last_checked_at, :utc_datetime
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(target, attrs) do
    target
    |> cast(attrs, [:project_id, :target_type, :value, :check_interval_hours, :last_checked_at, :status, :metadata])
    |> validate_required([:project_id, :target_type, :value, :status])
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:check_interval_hours, greater_than: 0)
    |> foreign_key_constraint(:project_id)
  end
end
