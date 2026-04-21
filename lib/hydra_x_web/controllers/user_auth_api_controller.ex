defmodule HydraXWeb.UserAuthAPIController do
  @moduledoc """
  Cycle 2 simple-auth endpoints. Dev-login swaps OAuth/magic-link for a
  direct email → user lookup (or create) so the frontend can mint a
  session cookie without an external identity provider.

  Routes:
    * `POST /api/v1/user_auth/dev_login` — `{email, display_name?}` →
      creates or finds user + personal workspace, sets session cookie.
    * `GET  /api/v1/user_auth/me`        — current user + workspaces.
    * `POST /api/v1/user_auth/logout`    — drops the session cookie.
  """

  use HydraXWeb, :controller

  alias HydraX.Accounts
  alias HydraXWeb.Plugs.UserAuth

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def dev_login(conn, %{"email" => email} = params) when is_binary(email) do
    unless dev_login_enabled?() do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "dev_login_disabled"})
    else
      email = String.trim(email)

      cond do
        email == "" ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "email_required"})

        true ->
          do_dev_login(conn, email, params["display_name"])
      end
    end
  end

  def dev_login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email_required"})
  end

  defp do_dev_login(conn, email, display_name) do
    case Accounts.get_user_by_email(email) do
      nil ->
        attrs = %{"email" => email, "display_name" => display_name || default_name(email)}

        case Accounts.create_user_with_workspace(attrs) do
          {:ok, %{user: user}} ->
            respond_with_session(conn, user)

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "user_create_failed", reason: inspect(reason)})
        end

      user ->
        {:ok, user} = Accounts.mark_email_verified(user)
        respond_with_session(conn, user)
    end
  end

  def me(conn, _params) do
    case conn.assigns[:current_user] do
      %HydraX.Accounts.User{} = user -> json(conn, %{data: user_payload(user)})
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "authentication_required"})
    end
  end

  def logout(conn, _params) do
    conn
    |> UserAuth.clear_user_session()
    |> json(%{data: %{signed_out: true}})
  end

  @doc """
  Identity bootstrap — seeds the signed-in user's shared scope with a
  starter set of nodes (principles, identity facts, values) from the
  onboarding form. Idempotent per node title; re-submitting updates.

  Expected payload: `{nodes: [%{node_type, title, body}, ...]}`
  """
  def identity_bootstrap(conn, %{"nodes" => nodes}) when is_list(nodes) do
    case conn.assigns[:current_user] do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "authentication_required"})

      user ->
        {:ok, scope} = HydraX.SharedMemory.ensure_scope_for_user(user.id)

        created =
          Enum.reduce(nodes, [], fn attrs, acc ->
            normalised =
              attrs
              |> Map.new(fn {k, v} -> {to_string(k), v} end)
              |> Map.take(["node_type", "title", "body"])

            case HydraX.SharedMemory.create_node(scope, normalised) do
              {:ok, node} -> [node | acc]
              _ -> acc
            end
          end)

        json(conn, %{data: %{seeded: length(created)}})
    end
  end

  def identity_bootstrap(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "nodes_required"})
  end

  defp respond_with_session(conn, user) do
    conn
    |> UserAuth.put_user_session(user)
    |> json(%{data: user_payload(user)})
  end

  defp user_payload(user) do
    %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      workspaces: Enum.map(Accounts.list_workspaces_for_user(user.id), &workspace_payload/1)
    }
  end

  defp workspace_payload(workspace) do
    %{id: workspace.id, name: workspace.name, slug: workspace.slug}
  end

  defp default_name(email) do
    email |> String.split("@") |> hd() |> String.capitalize()
  end

  defp dev_login_enabled? do
    Application.get_env(:hydra_x, :dev_login_enabled, true)
  end
end
