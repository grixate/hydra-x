defmodule HydraX.Runtime.CoordinationLease do
  use Ecto.Schema
  import Ecto.Changeset

  schema "coordination_leases" do
    field :name, :string
    field :owner, :string
    field :owner_node, :string
    field :lease_type, :string, default: "exclusive"
    field :expires_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(lease, attrs) do
    lease
    |> cast(attrs, [:name, :owner, :owner_node, :lease_type, :expires_at, :metadata])
    |> validate_required([:name, :owner, :owner_node, :lease_type, :expires_at])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:owner, min: 1, max: 255)
    |> validate_length(:owner_node, min: 1, max: 255)
    |> validate_inclusion(:lease_type, ["exclusive"])
    |> unique_constraint(:name)
  end
end
