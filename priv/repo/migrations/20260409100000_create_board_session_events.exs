defmodule HydraX.Repo.Migrations.CreateBoardSessionEvents do
  use Ecto.Migration

  def change do
    create table(:board_session_events) do
      add :board_session_id, :integer, null: false
      add :event_type, :string, null: false
      add :actor_type, :string, null: false
      add :actor_name, :string, null: false
      add :target_type, :string
      add :target_id, :integer
      add :target_title, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:board_session_events, [:board_session_id])
    create index(:board_session_events, [:board_session_id, :inserted_at])
  end
end
