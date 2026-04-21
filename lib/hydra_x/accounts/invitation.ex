defmodule HydraX.Accounts.Invitation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner member)

  schema "invitations" do
    field :email, :string
    field :role, :string, default: "member"
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :workspace, HydraX.Accounts.Workspace
    belongs_to :invited_by, HydraX.Accounts.User, foreign_key: :invited_by_user_id

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :workspace_id,
      :email,
      :invited_by_user_id,
      :role,
      :token_hash,
      :expires_at,
      :accepted_at,
      :revoked_at
    ])
    |> validate_required([:workspace_id, :email, :role, :token_hash, :expires_at])
    |> validate_inclusion(:role, @roles)
    |> update_change(:email, fn email ->
      if is_binary(email), do: email |> String.trim() |> String.downcase(), else: email
    end)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:invited_by_user_id)
  end
end
