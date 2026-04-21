defmodule HydraX.Repo.Migrations.AddDeferredUntilToAgentTasks do
  @moduledoc """
  Stream B3.3 — snooze/defer support.

  When a user defers a task in the Needs You or Blockers tab, the task
  temporarily disappears from the visible list until `deferred_until`.
  The underlying state is unchanged; the timestamp is purely a UI gate.
  """

  use Ecto.Migration

  def change do
    alter table(:agent_tasks) do
      add :deferred_until, :utc_datetime_usec
    end

    create index(:agent_tasks, [:project_id, :deferred_until])
  end
end
