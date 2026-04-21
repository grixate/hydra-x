defmodule HydraX.Accounts.SharedScope do
  @moduledoc """
  The "You" scope per `shared-memory-spec.md`. One per user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shared_scopes" do
    field :display_name, :string, default: "You"
    field :metadata, :map, default: %{}

    belongs_to :owner, HydraX.Accounts.User, foreign_key: :owner_user_id
    has_many :nodes, HydraX.SharedMemory.Node, foreign_key: :shared_scope_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(scope, attrs) do
    scope
    |> cast(attrs, [:owner_user_id, :display_name, :metadata])
    |> validate_required([:owner_user_id, :display_name])
    |> unique_constraint(:owner_user_id)
    |> foreign_key_constraint(:owner_user_id)
  end
end
