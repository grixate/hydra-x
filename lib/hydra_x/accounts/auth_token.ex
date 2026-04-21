defmodule HydraX.Accounts.AuthToken do
  @moduledoc """
  Server-stored representation of an auth token (magic link, etc.). The raw
  token value is **never stored** — only `token_hash` = `sha256(raw_token)`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @contexts ~w(magic_link session invitation)

  schema "auth_tokens" do
    field :email, :string
    field :context, :string
    field :token_hash, :string
    field :sent_to, :string
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    belongs_to :user, HydraX.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def contexts, do: @contexts

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :email, :context, :token_hash, :sent_to, :expires_at, :consumed_at])
    |> validate_required([:context, :token_hash, :expires_at])
    |> validate_inclusion(:context, @contexts)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
  end
end
