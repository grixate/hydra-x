defmodule HydraX.Product.BoardSessionEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "board_session_events" do
    field :board_session_id, :integer
    field :event_type, :string
    field :actor_type, :string
    field :actor_name, :string
    field :target_type, :string
    field :target_id, :integer
    field :target_title, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :board_session_id,
      :event_type,
      :actor_type,
      :actor_name,
      :target_type,
      :target_id,
      :target_title,
      :metadata
    ])
    |> validate_required([:board_session_id, :event_type, :actor_type, :actor_name])
  end
end
