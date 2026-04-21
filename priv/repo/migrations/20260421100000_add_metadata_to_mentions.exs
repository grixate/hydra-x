defmodule HydraX.Repo.Migrations.AddMetadataToMentions do
  @moduledoc """
  Stream B1.5 — carry ambiguous-intent flags + inference confidence on
  the Mention so the frontend disambiguation UI can act on them.
  """

  use Ecto.Migration

  def change do
    alter table(:mentions) do
      add :metadata, :map, null: false, default: %{}
    end
  end
end
