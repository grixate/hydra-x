defmodule HydraX.Repo.Migrations.CreateSharedMemory do
  @moduledoc """
  Stream A3.1 + A3.2 — shared-memory data layer.

    * `shared_scopes` — one per user (spec §4): the "You" root
    * `shared_memory_nodes` — the six shared node types (Principle,
      Heuristic, Method, MentalModel, IdentityFact, Value) in a single
      table keyed by `node_type`. Kept as one table to make cross-type
      queries (Coherence scans, distillation lineage) cheap.
    * `distillations` — link table from a shared_memory_node back to the
      project-level episodes that supported its creation (spec §4)

  One `SharedScope` is auto-created per existing user via backfill.
  """

  use Ecto.Migration

  def change do
    create table(:shared_scopes, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")

      add :owner_user_id,
          references(:users, type: :uuid, on_delete: :delete_all),
          null: false

      add :display_name, :string, null: false, default: "You"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:shared_scopes, [:owner_user_id])

    # Backfill: one SharedScope per existing user.
    execute(
      """
      INSERT INTO shared_scopes (id, owner_user_id, display_name, metadata, inserted_at, updated_at)
      SELECT uuid_generate_v4(), u.id, 'You', '{}'::jsonb, NOW(), NOW()
      FROM users u
      LEFT JOIN shared_scopes s ON s.owner_user_id = u.id
      WHERE s.id IS NULL
      """,
      "SELECT 1"
    )

    # ------------------------------------------------------------------
    # Shared memory nodes (spec §3). One table, typed by node_type, so
    # Coherence & distillation lineage queries are uniform.
    # ------------------------------------------------------------------

    create table(:shared_memory_nodes) do
      add :shared_scope_id,
          references(:shared_scopes, type: :uuid, on_delete: :delete_all),
          null: false

      add :node_type, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :last_referenced_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:shared_memory_nodes, [:shared_scope_id, :node_type])
    create index(:shared_memory_nodes, [:status])
    create index(:shared_memory_nodes, [:last_referenced_at])

    create constraint(:shared_memory_nodes, :shared_memory_nodes_type_check,
             check:
               "node_type IN ('principle','heuristic','method','mental_model','identity_fact','value')"
           )

    # ------------------------------------------------------------------
    # Distillations — links shared node → supporting project episode.
    # A shared node typically has many distillation links (spec §4).
    # ------------------------------------------------------------------

    create table(:distillations) do
      add :shared_node_id,
          references(:shared_memory_nodes, on_delete: :delete_all),
          null: false

      add :episode_project_id, references(:projects, on_delete: :nilify_all)
      add :episode_node_type, :string, null: false
      add :episode_node_id, :integer, null: false
      add :weight, :float, default: 1.0
      add :context_snippet, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:distillations, [:shared_node_id])
    create index(:distillations, [:episode_project_id])
    create index(:distillations, [:episode_node_type, :episode_node_id])

    create unique_index(:distillations, [:shared_node_id, :episode_node_type, :episode_node_id],
             name: :distillations_unique_link_index
           )
  end
end
