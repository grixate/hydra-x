defmodule HydraX.Accounts.Workspace do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :created_by, HydraX.Accounts.User, foreign_key: :created_by_user_id
    has_many :memberships, HydraX.Accounts.WorkspaceMembership

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :slug, :created_by_user_id, :deleted_at])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &normalise_slug/1)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/,
      message: "lowercase letters, digits, hyphens only"
    )
    |> validate_length(:slug, min: 1, max: 80)
    |> validate_length(:name, min: 1, max: 120)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:created_by_user_id)
  end

  defp normalise_slug(nil), do: nil
  defp normalise_slug(slug) when is_binary(slug), do: slug |> String.trim() |> String.downcase()
end
