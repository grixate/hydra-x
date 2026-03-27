defmodule HydraX.Runtime.OperatorSecret do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Security.Password

  schema "hx_operator_secrets" do
    field :scope, :string, default: "control_plane"
    field :password_hash, :string
    field :password_salt, :string
    field :last_rotated_at, :utc_datetime_usec
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(secret, attrs) do
    secret
    |> cast(attrs, [:scope, :password, :password_confirmation])
    |> validate_required([:scope])
    |> validate_password_fields()
    |> unique_constraint(:scope)
    |> maybe_put_password_hash()
  end

  def verify_password(%__MODULE__{} = secret, password) when is_binary(password) do
    Password.verify_password(password, secret.password_salt || "", secret.password_hash || "")
  end

  defp validate_password_fields(changeset) do
    password = get_change(changeset, :password)
    confirmation = get_change(changeset, :password_confirmation)

    if is_nil(password) and is_nil(confirmation) do
      changeset
    else
      changeset
      |> validate_required([:password, :password_confirmation])
      |> validate_length(:password, min: 12, max: 128)
      |> validate_confirmation(:password, message: "does not match password confirmation")
    end
  end

  defp maybe_put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        %{salt: salt, hash: hash} = Password.hash_password(password)

        changeset
        |> put_change(:password_salt, salt)
        |> put_change(:password_hash, hash)
        |> put_change(:last_rotated_at, DateTime.utc_now())
    end
  end
end
