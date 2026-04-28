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
    field :password_hash, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :operator_at, :utc_datetime_usec
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
    |> validate_email()
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> changeset(attrs)
    |> password_changeset(attrs, opts)
  end

  def password_changeset(user_or_changeset, attrs, opts \\ []) do
    user_or_changeset
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 128)
    |> validate_confirmation(:password, message: "does not match password")
    |> maybe_hash_password(opts)
  end

  def operator_changeset(user, now \\ DateTime.utc_now()) do
    change(user, operator_at: user.operator_at || DateTime.truncate(now, :microsecond))
  end

  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and is_binary(password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &normalise_email/1)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 320)
    |> unique_constraint(:email)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? and changeset.valid? and is_binary(password) do
      changeset
      |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
      |> delete_change(:password_confirmation)
    else
      changeset
    end
  end

  defp normalise_email(nil), do: nil

  defp normalise_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()
end
