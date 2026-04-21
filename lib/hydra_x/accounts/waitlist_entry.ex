defmodule HydraX.Accounts.WaitlistEntry do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "waitlist_entries" do
    field :email, :string
    field :name, :string
    field :context, :string
    field :referrer_url, :string
    field :granted_at, :utc_datetime_usec

    belongs_to :granted_by, HydraX.Accounts.User, foreign_key: :granted_by_user_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:email, :name, :context, :referrer_url, :granted_at, :granted_by_user_id])
    |> validate_required([:email])
    |> update_change(:email, fn email ->
      if is_binary(email), do: email |> String.trim() |> String.downcase(), else: email
    end)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> unique_constraint(:email)
    |> foreign_key_constraint(:granted_by_user_id)
  end
end
