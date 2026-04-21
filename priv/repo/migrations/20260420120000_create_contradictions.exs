defmodule HydraX.Repo.Migrations.CreateContradictions do
  @moduledoc """
  Cycle 2 hero — Coherence data model per `coherence-spec.md` §4.

  `contradictions` stores each detected contradiction; `contradiction_events`
  is the append-only audit log of status changes.

  Node references are polymorphic via `(node_type, node_id)` pairs plus
  an explicit `node_scope` ("project" / "shared"). This matches the rest
  of Hydra's graph — nodes live in per-type tables with integer PKs.
  """

  use Ecto.Migration

  def change do
    create table(:contradictions) do
      add :project_id, references(:projects, on_delete: :delete_all)
      add :shared_scope_id, references(:shared_scopes, type: :uuid, on_delete: :nilify_all)

      add :mode, :string, null: false

      add :node_a_type, :string, null: false
      add :node_a_id, :integer, null: false
      add :node_a_scope, :string, null: false, default: "project"

      add :node_b_type, :string, null: false
      add :node_b_id, :integer, null: false
      add :node_b_scope, :string, null: false, default: "project"

      add :explanation, :text
      add :severity, :string, null: false, default: "medium"
      add :severity_reason, :text
      add :confidence, :string, null: false, default: "medium"

      add :context_diff, :map
      add :suggested_resolutions, {:array, :map}, default: []

      add :status, :string, null: false, default: "open"
      add :status_reason, :text

      add :resolved_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime_usec

      add :detected_at, :utc_datetime_usec, null: false
      add :last_confirmed_at, :utc_datetime_usec, null: false
      add :dismissed_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    # Filtering
    create index(:contradictions, [:project_id, :status])
    create index(:contradictions, [:shared_scope_id, :status])
    create index(:contradictions, [:mode, :status])
    create index(:contradictions, [:status, :detected_at])

    # Node lookup
    create index(:contradictions, [:node_a_type, :node_a_id])
    create index(:contradictions, [:node_b_type, :node_b_id])

    # Dedupe: one open contradiction per ordered node pair per mode
    create unique_index(
             :contradictions,
             [:mode, :node_a_type, :node_a_id, :node_b_type, :node_b_id],
             name: :contradictions_unique_pair_index,
             where: "status IN ('open', 'under_review')"
           )

    create constraint(:contradictions, :contradictions_mode_check,
             check:
               "mode IN ('in_project','cross_project','principle_vs_practice','intra_shared_memory')"
           )

    create constraint(:contradictions, :contradictions_severity_check,
             check: "severity IN ('low','medium','high')"
           )

    create constraint(:contradictions, :contradictions_status_check,
             check:
               "status IN ('open','under_review','resolved','dismissed','stale','acknowledged_tension')"
           )

    # -----------------------------------------------------------------

    create table(:contradiction_events) do
      add :contradiction_id,
          references(:contradictions, on_delete: :delete_all),
          null: false

      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :actor_type, :string, null: false
      add :actor_id, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contradiction_events, [:contradiction_id, :inserted_at])
  end
end
