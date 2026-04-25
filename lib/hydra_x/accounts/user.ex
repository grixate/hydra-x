defmodule HydraX.Accounts.User do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
    field :email_verified_at, :utc_datetime_usec
    field :last_sign_in_at, :utc_datetime_usec

    has_many :workspace_memberships, HydraX.Accounts.WorkspaceMembership
    has_many :workspaces, through: [:workspace_memberships, :workspace]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :display_name, :avatar_url, :email_verified_at, :last_sign_in_at])
    |> validate_required([:email])
    |> update_change(:email, &normalise_email/1)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 320)
    |> unique_constraint(:email)
  end

  defp normalise_email(nil), do: nil

  defp normalise_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()
end
