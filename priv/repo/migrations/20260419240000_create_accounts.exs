defmodule HydraX.Repo.Migrations.CreateAccounts do
  @moduledoc """
  Auth-minimal foundation per `auth-minimal-spec.md`:

    * `users`                  — real user accounts
    * `workspaces`             — tenancy root (projects scope below this)
    * `workspace_memberships`  — user ↔ workspace with role
    * `invitations`            — workspace invites with secure tokens
    * `waitlist_entries`       — waitlist for self-signup
    * `auth_tokens`            — short-lived magic-link / session tokens

  All new tables use UUID primary keys per spec §3. The existing `projects`
  table keeps its integer primary key; `workspace_id` is added as a nullable
  UUID FK here and backfilled + NOT-NULL-constrained in a follow-up
  migration once the default workspace exists.

  This migration ships the **data model only** (Week 1 of spec §15).
  OAuth, email templates, UI, router gates, and session integration are
  deferred to follow-up work — they need external dependencies beyond the
  data layer.
  """

  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", "SELECT 1"
    execute "CREATE EXTENSION IF NOT EXISTS citext", "SELECT 1"

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")
      add :email, :citext, null: false
      add :display_name, :string
      add :avatar_url, :string
      add :email_verified_at, :utc_datetime_usec
      add :last_sign_in_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:workspaces, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")
      add :name, :string, null: false
      add :slug, :string, null: false
      add :created_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:slug])
    create index(:workspaces, [:created_by_user_id])

    create table(:workspace_memberships, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")
      add :workspace_id, references(:workspaces, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :joined_at, :utc_datetime_usec, null: false
      add :invited_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspace_memberships, [:workspace_id, :user_id])
    create index(:workspace_memberships, [:user_id])

    create table(:invitations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")
      add :workspace_id, references(:workspaces, type: :uuid, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :invited_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :role, :string, null: false, default: "member"
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitations, [:token_hash])
    create index(:invitations, [:workspace_id])
    create index(:invitations, [:email])

    create table(:waitlist_entries, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")
      add :email, :citext, null: false
      add :name, :string
      add :context, :text
      add :referrer_url, :string
      add :granted_at, :utc_datetime_usec
      add :granted_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:waitlist_entries, [:email])
    create index(:waitlist_entries, [:granted_at])

    # Auth tokens: short-lived magic links, session bearer tokens, etc.
    # One row per issued token; we hash the token value at rest so DB
    # compromise doesn't grant immediate use.
    create table(:auth_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v4()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :email, :citext
      add :context, :string, null: false
      add :token_hash, :string, null: false
      add :sent_to, :string
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:auth_tokens, [:token_hash])
    create index(:auth_tokens, [:user_id, :context])
    create index(:auth_tokens, [:expires_at])

    # Projects scoping: nullable UUID FK for now. A default workspace will
    # be seeded + backfill run in a follow-up migration once we know which
    # user owns the data (in dev: the first admin user).
    alter table(:projects) do
      add :workspace_id, references(:workspaces, type: :uuid, on_delete: :restrict)
    end

    create index(:projects, [:workspace_id])
  end
end
