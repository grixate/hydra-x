defmodule HydraX.Accounts do
  @moduledoc """
  Context for user accounts, workspaces, memberships, invitations,
  waitlist entries, and short-lived auth tokens.

  Cycle 1 (`auth-minimal-spec.md`) ships only the **data layer** through
  this context. OAuth, email sending, UI, and router gating are deferred
  to follow-up work — they each need external dependencies (OAuth keys,
  email provider, frontend design pass) that are best tackled outside a
  single implementation sprint.

  The public surface here is organised so the follow-up work can wire in
  HTTP, email, and OAuth layers without revisiting the data model.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Accounts.AuthToken
  alias HydraX.Accounts.Invitation
  alias HydraX.Accounts.User
  alias HydraX.Accounts.WaitlistEntry
  alias HydraX.Accounts.Workspace
  alias HydraX.Accounts.WorkspaceMembership

  ## ------------------------------------------------------------------
  ## Users
  ## ------------------------------------------------------------------

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(nil), do: nil

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: normalise_email(email))
  end

  def operator_user_exists? do
    Repo.exists?(from u in User, where: not is_nil(u.operator_at))
  end

  def get_operator_user(id) when is_binary(id) do
    Repo.get_by(User, id: id) |> operator_or_nil()
  end

  def change_user_registration(attrs \\ %{}) do
    User.registration_changeset(%User{}, attrs, hash_password: false)
  end

  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Register the first local user and promote them to the instance operator.
  Once an operator exists, public registration is closed.
  """
  def register_first_operator(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      if operator_user_exists?(), do: Repo.rollback(:registration_closed)

      with {:ok, user} <-
             %User{}
             |> User.registration_changeset(
               attrs
               |> Map.new(fn {k, v} -> {to_string(k), v} end)
               |> Map.put("operator_at", now)
             )
             |> Ecto.Changeset.put_change(:operator_at, now)
             |> Ecto.Changeset.put_change(:email_verified_at, now)
             |> Repo.insert(),
           {:ok, workspace} <- create_personal_workspace(user),
           {:ok, membership} <-
             add_member(workspace, user, %{role: "owner", invited_by_user_id: nil}) do
        %{user: user, workspace: workspace, membership: membership}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    if User.valid_password?(user, password) do
      user
      |> Ecto.Changeset.change(last_sign_in_at: DateTime.utc_now())
      |> Repo.update()
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_credentials}
    end
  end

  def authenticate_user(_, _) do
    User.valid_password?(nil, nil)
    {:error, :invalid_credentials}
  end

  def operator?(%User{operator_at: %DateTime{}}), do: true
  def operator?(_), do: false

  def update_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Create a user and auto-create their personal workspace per spec §4 / §6.
  Returns `{:ok, %{user, workspace, membership}}` or an error changeset.
  """
  def create_user_with_workspace(attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- create_user(attrs),
           {:ok, workspace} <- create_personal_workspace(user),
           {:ok, membership} <-
             add_member(workspace, user, %{role: "owner", invited_by_user_id: nil}) do
        %{user: user, workspace: workspace, membership: membership}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user |> User.changeset(attrs) |> Repo.update()
  end

  def mark_email_verified(%User{} = user, now \\ DateTime.utc_now()) do
    user
    |> Ecto.Changeset.change(
      email_verified_at: user.email_verified_at || now,
      last_sign_in_at: now
    )
    |> Repo.update()
  end

  defp operator_or_nil(%User{} = user), do: if(operator?(user), do: user)
  defp operator_or_nil(_), do: nil

  ## ------------------------------------------------------------------
  ## Workspaces
  ## ------------------------------------------------------------------

  def get_workspace(id), do: Repo.get(Workspace, id)
  def get_workspace_by_slug(slug), do: Repo.get_by(Workspace, slug: slug)

  def ensure_default_workspace! do
    Repo.one(
      from w in Workspace,
        where: is_nil(w.deleted_at),
        order_by: [asc: w.inserted_at],
        limit: 1
    ) || create_system_workspace!()
  end

  def default_workspace_id do
    ensure_default_workspace!().id
  end

  @doc """
  Create a workspace. Ensures slug uniqueness with an appended `-2`, `-3`,
  … on collision (spec §16 open decision: yes, transparent to user).
  """
  def create_workspace(attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> maybe_derive_slug()

    attempt_create_workspace(attrs, 0)
  end

  defp attempt_create_workspace(attrs, attempts) when attempts < 10 do
    base_slug = attrs["slug"]
    candidate = if attempts == 0, do: base_slug, else: "#{base_slug}-#{attempts + 1}"

    %Workspace{}
    |> Workspace.changeset(Map.put(attrs, "slug", candidate))
    |> Repo.insert()
    |> case do
      {:error, %Ecto.Changeset{errors: errors}} = err ->
        if Keyword.has_key?(errors, :slug) and slug_collision?(errors) do
          attempt_create_workspace(attrs, attempts + 1)
        else
          err
        end

      ok ->
        ok
    end
  end

  defp attempt_create_workspace(_attrs, _attempts), do: {:error, :slug_collision_exhausted}

  defp slug_collision?(errors) do
    case errors[:slug] do
      {_, opts} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end
  end

  defp maybe_derive_slug(attrs) do
    case attrs["slug"] do
      value when is_binary(value) and value != "" ->
        attrs

      _ ->
        Map.put(attrs, "slug", slugify(attrs["name"] || ""))
    end
  end

  defp slugify(""), do: "workspace"

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "workspace"
      s -> s
    end
  end

  defp create_personal_workspace(%User{} = user) do
    name = (user.display_name || email_username(user.email)) <> "'s Workspace"

    create_workspace(%{
      "name" => name,
      "slug" => slugify(user.display_name || email_username(user.email)),
      "created_by_user_id" => user.id
    })
  end

  defp create_system_workspace! do
    case create_user_with_workspace(%{
           "email" => "system@hydra.local",
           "display_name" => "System"
         }) do
      {:ok, %{workspace: workspace}} ->
        workspace

      {:error, _reason} ->
        Repo.one!(
          from w in Workspace,
            where: is_nil(w.deleted_at),
            order_by: [asc: w.inserted_at],
            limit: 1
        )
    end
  end

  defp email_username(email) when is_binary(email), do: email |> String.split("@") |> hd()
  defp email_username(_), do: "user"

  def list_workspaces_for_user(user_id) do
    from(w in Workspace,
      join: m in WorkspaceMembership,
      on: m.workspace_id == w.id,
      where: m.user_id == ^user_id and is_nil(w.deleted_at),
      order_by: [asc: w.name]
    )
    |> Repo.all()
  end

  def workspace_member?(workspace_id, user_id) do
    Repo.exists?(
      from m in WorkspaceMembership,
        where: m.workspace_id == ^workspace_id and m.user_id == ^user_id
    )
  end

  def workspace_owner?(workspace_id, user_id) do
    Repo.exists?(
      from m in WorkspaceMembership,
        where: m.workspace_id == ^workspace_id and m.user_id == ^user_id and m.role == "owner"
    )
  end

  ## ------------------------------------------------------------------
  ## Memberships
  ## ------------------------------------------------------------------

  def add_member(%Workspace{} = workspace, %User{} = user, attrs \\ %{}) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("workspace_id", workspace.id)
      |> Map.put("user_id", user.id)
      |> Map.put_new("role", "member")
      |> Map.put_new("joined_at", DateTime.utc_now())
    )
    |> Repo.insert()
  end

  def remove_member(%Workspace{} = workspace, %User{} = user) do
    # Guard: never remove the last owner (spec §6).
    case ensure_not_last_owner(workspace.id, user.id) do
      :ok ->
        from(m in WorkspaceMembership,
          where: m.workspace_id == ^workspace.id and m.user_id == ^user.id
        )
        |> Repo.delete_all()
        |> case do
          {0, _} -> {:error, :not_found}
          {_, _} -> :ok
        end

      err ->
        err
    end
  end

  def change_role(%Workspace{} = workspace, %User{} = user, new_role)
      when new_role in ~w(owner member) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      %WorkspaceMembership{role: "owner"} = membership when new_role != "owner" ->
        case ensure_not_last_owner(workspace.id, user.id) do
          :ok -> update_membership_role(membership, new_role)
          err -> err
        end

      membership ->
        update_membership_role(membership, new_role)
    end
  end

  defp update_membership_role(membership, new_role) do
    membership
    |> Ecto.Changeset.change(role: new_role)
    |> Repo.update()
  end

  defp ensure_not_last_owner(workspace_id, user_id) do
    owners =
      from(m in WorkspaceMembership,
        where: m.workspace_id == ^workspace_id and m.role == "owner"
      )
      |> Repo.aggregate(:count, :id)

    leaving_owner? =
      Repo.exists?(
        from m in WorkspaceMembership,
          where: m.workspace_id == ^workspace_id and m.user_id == ^user_id and m.role == "owner"
      )

    if leaving_owner? and owners <= 1, do: {:error, :last_owner}, else: :ok
  end

  ## ------------------------------------------------------------------
  ## Invitations
  ## ------------------------------------------------------------------

  def create_invitation(%Workspace{} = workspace, attrs) do
    {raw_token, token_hash} = fresh_token()

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("workspace_id", workspace.id)
      |> Map.put("token_hash", token_hash)
      |> Map.put_new("expires_at", DateTime.add(DateTime.utc_now(), 7, :day))
      |> Map.put_new("role", "member")

    case %Invitation{} |> Invitation.changeset(attrs) |> Repo.insert() do
      {:ok, invitation} -> {:ok, invitation, raw_token}
      err -> err
    end
  end

  @doc """
  Consume an invitation token. Returns `{:ok, invitation, user}` on
  success; also creates the user + membership transactionally if the
  email doesn't have a user yet.
  """
  def accept_invitation(raw_token, user_attrs \\ %{}) do
    hash = hash_token(raw_token)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      invitation =
        from(i in Invitation,
          where:
            i.token_hash == ^hash and is_nil(i.accepted_at) and is_nil(i.revoked_at) and
              i.expires_at >= ^now
        )
        |> Repo.one()

      if is_nil(invitation) do
        Repo.rollback(:invitation_invalid)
      end

      user =
        get_user_by_email(invitation.email) || ensure_user_for_invitation(invitation, user_attrs)

      membership_attrs = %{
        "role" => invitation.role,
        "joined_at" => now,
        "invited_by_user_id" => invitation.invited_by_user_id
      }

      workspace = Repo.get!(Workspace, invitation.workspace_id)

      case add_member(workspace, user, membership_attrs) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{errors: errors}} ->
          # Already a member? treat as success so repeated invite-accepts
          # are idempotent.
          unless Keyword.has_key?(errors, :workspace_id) or
                   Keyword.has_key?(errors, :user_id) do
            Repo.rollback(:membership_failed)
          end
      end

      {:ok, accepted} =
        invitation
        |> Ecto.Changeset.change(accepted_at: now)
        |> Repo.update()

      {accepted, user}
    end)
  end

  @doc """
  Accept an invitation while setting a local password for users who do not
  already have one.
  """
  def register_invited_user(raw_token, user_attrs) do
    hash = hash_token(raw_token)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      invitation =
        from(i in Invitation,
          where:
            i.token_hash == ^hash and is_nil(i.accepted_at) and is_nil(i.revoked_at) and
              i.expires_at >= ^now
        )
        |> Repo.one()

      if is_nil(invitation), do: Repo.rollback(:invitation_invalid)

      attrs =
        user_attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("email", invitation.email)

      user =
        case get_user_by_email(invitation.email) do
          nil ->
            case %User{}
                 |> User.registration_changeset(attrs)
                 |> Ecto.Changeset.put_change(:email_verified_at, now)
                 |> Repo.insert() do
              {:ok, user} -> user
              {:error, changeset} -> Repo.rollback(changeset)
            end

          %User{password_hash: nil} = user ->
            case user
                 |> User.password_changeset(attrs)
                 |> Ecto.Changeset.put_change(:email_verified_at, user.email_verified_at || now)
                 |> Repo.update() do
              {:ok, user} -> user
              {:error, changeset} -> Repo.rollback(changeset)
            end

          user ->
            user
        end

      membership_attrs = %{
        "role" => invitation.role,
        "joined_at" => now,
        "invited_by_user_id" => invitation.invited_by_user_id
      }

      workspace = Repo.get!(Workspace, invitation.workspace_id)

      case add_member(workspace, user, membership_attrs) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{errors: errors}} ->
          unless Keyword.has_key?(errors, :workspace_id) or
                   Keyword.has_key?(errors, :user_id) do
            Repo.rollback(:membership_failed)
          end
      end

      {:ok, accepted} =
        invitation
        |> Ecto.Changeset.change(accepted_at: now)
        |> Repo.update()

      %{invitation: accepted, user: user}
    end)
  end

  defp ensure_user_for_invitation(%Invitation{email: email}, user_attrs) do
    {:ok, user} =
      create_user(
        user_attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("email", email)
      )

    user
  end

  def revoke_invitation(%Invitation{} = invitation) do
    invitation
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now())
    |> Repo.update()
  end

  def list_pending_invitations(workspace_id) do
    now = DateTime.utc_now()

    from(i in Invitation,
      where:
        i.workspace_id == ^workspace_id and is_nil(i.accepted_at) and
          is_nil(i.revoked_at) and i.expires_at >= ^now,
      order_by: [desc: i.inserted_at]
    )
    |> Repo.all()
  end

  ## ------------------------------------------------------------------
  ## Waitlist
  ## ------------------------------------------------------------------

  def add_to_waitlist(attrs) do
    %WaitlistEntry{} |> WaitlistEntry.changeset(attrs) |> Repo.insert()
  end

  def grant_waitlist_access(email, granted_by_user_id) when is_binary(email) do
    entry = Repo.get_by(WaitlistEntry, email: normalise_email(email))

    if is_nil(entry) do
      {:error, :not_found}
    else
      entry
      |> WaitlistEntry.changeset(%{
        "granted_at" => DateTime.utc_now(),
        "granted_by_user_id" => granted_by_user_id
      })
      |> Repo.update()
    end
  end

  def waitlist_granted?(email) when is_binary(email) do
    Repo.exists?(
      from w in WaitlistEntry,
        where: w.email == ^normalise_email(email) and not is_nil(w.granted_at)
    )
  end

  def list_waitlist(opts \\ []) do
    only_ungranted = Keyword.get(opts, :only_ungranted, false)
    limit = Keyword.get(opts, :limit, 500)

    WaitlistEntry
    |> maybe_ungranted(only_ungranted)
    |> order_by([w], desc: w.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_ungranted(query, true), do: where(query, [w], is_nil(w.granted_at))
  defp maybe_ungranted(query, _), do: query

  ## ------------------------------------------------------------------
  ## Auth tokens (magic links)
  ## ------------------------------------------------------------------

  @magic_link_ttl_minutes 15
  @password_reset_ttl_minutes 30

  @doc """
  Issue a magic-link token. Returns `{:ok, %AuthToken{}, raw_token}`. The
  raw token must be delivered to the user (via email) — it's the only time
  you'll see it.
  """
  def issue_magic_link(email, opts \\ []) do
    {raw_token, token_hash} = fresh_token()
    expires_at = DateTime.add(DateTime.utc_now(), @magic_link_ttl_minutes * 60, :second)
    normalized = normalise_email(email)
    user = get_user_by_email(normalized)

    attrs = %{
      "user_id" => user && user.id,
      "email" => normalized,
      "context" => "magic_link",
      "token_hash" => token_hash,
      "sent_to" => Keyword.get(opts, :sent_to, normalized),
      "expires_at" => expires_at
    }

    case %AuthToken{} |> AuthToken.changeset(attrs) |> Repo.insert() do
      {:ok, token} -> {:ok, token, raw_token}
      err -> err
    end
  end

  @doc """
  Consume a magic-link token. On success returns `{:ok, user}`; creates
  the user + personal workspace on first use if the token's email doesn't
  have an account yet.
  """
  def consume_magic_link(raw_token) do
    hash = hash_token(raw_token)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      token =
        from(t in AuthToken,
          where:
            t.token_hash == ^hash and t.context == "magic_link" and is_nil(t.consumed_at) and
              t.expires_at >= ^now
        )
        |> Repo.one()

      if is_nil(token), do: Repo.rollback(:invalid_or_expired)

      user =
        case token.user_id do
          nil -> ensure_user_for_token(token)
          id -> Repo.get!(User, id)
        end

      {:ok, _} =
        token
        |> Ecto.Changeset.change(consumed_at: now, user_id: user.id)
        |> Repo.update()

      {:ok, verified} = mark_email_verified(user, now)

      verified
    end)
  end

  def issue_password_reset(email, opts \\ []) do
    normalized = normalise_email(email)

    case get_user_by_email(normalized) do
      nil ->
        {:ok, nil, nil}

      %User{} = user ->
        {raw_token, token_hash} = fresh_token()
        expires_at = DateTime.add(DateTime.utc_now(), @password_reset_ttl_minutes * 60, :second)

        attrs = %{
          "user_id" => user.id,
          "email" => normalized,
          "context" => "password_reset",
          "token_hash" => token_hash,
          "sent_to" => Keyword.get(opts, :sent_to, normalized),
          "expires_at" => expires_at
        }

        case %AuthToken{} |> AuthToken.changeset(attrs) |> Repo.insert() do
          {:ok, token} -> {:ok, token, raw_token}
          err -> err
        end
    end
  end

  def reset_user_password(raw_token, attrs) do
    hash = hash_token(raw_token)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      token =
        from(t in AuthToken,
          where:
            t.token_hash == ^hash and t.context == "password_reset" and
              is_nil(t.consumed_at) and t.expires_at >= ^now
        )
        |> Repo.one()

      if is_nil(token) or is_nil(token.user_id), do: Repo.rollback(:invalid_or_expired)

      user = Repo.get!(User, token.user_id)

      case update_user_password(user, attrs) do
        {:ok, user} ->
          {:ok, _} =
            token
            |> Ecto.Changeset.change(consumed_at: now)
            |> Repo.update()

          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp ensure_user_for_token(%AuthToken{email: email}) do
    case get_user_by_email(email) do
      nil ->
        {:ok, %{user: user}} =
          create_user_with_workspace(%{"email" => email, "display_name" => email_username(email)})

        user

      user ->
        user
    end
  end

  ## ------------------------------------------------------------------
  ## Shared helpers
  ## ------------------------------------------------------------------

  defp fresh_token do
    raw = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {raw, hash_token(raw)}
  end

  defp hash_token(raw) when is_binary(raw) do
    :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower)
  end

  defp normalise_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalise_email(other), do: other
end
