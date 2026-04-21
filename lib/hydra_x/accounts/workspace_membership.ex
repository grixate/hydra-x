defmodule HydraX.Accounts.WorkspaceMembership do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner member)

  schema "workspace_memberships" do
    field :role, :string, default: "member"
    field :joined_at, :utc_datetime_usec

    belongs_to :workspace, HydraX.Accounts.Workspace
    belongs_to :user, HydraX.Accounts.User
    belongs_to :invited_by, HydraX.Accounts.User, foreign_key: :invited_by_user_id

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:workspace_id, :user_id, :role, :joined_at, :invited_by_user_id])
    |> validate_required([:workspace_id, :user_id, :role, :joined_at])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:workspace_id, :user_id])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:invited_by_user_id)
  end
end
