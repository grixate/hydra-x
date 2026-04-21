defmodule HydraX.Repo.Migrations.AddReviewedAtToSources do
  @moduledoc """
  Stream B4.3 — first-class "unreviewed" filter in the Library.

  Adds a `reviewed_at` timestamp to `sources`. NULL means the user hasn't
  reviewed the source yet. The Library filter chip queries for `IS NULL`.
  """

  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :reviewed_at, :utc_datetime_usec
    end

    create index(:sources, [:project_id, :reviewed_at])
  end
end
