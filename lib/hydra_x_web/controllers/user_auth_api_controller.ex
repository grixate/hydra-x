defmodule HydraXWeb.UserAuthAPIController do
  @moduledoc """
  Local user-auth endpoints for self-hosted Hydra.
  """

  use HydraXWeb, :controller

  require Logger

  alias HydraX.Accounts
  alias HydraX.Security.LoginThrottle
  alias HydraXWeb.DevAuth
  alias HydraXWeb.OperatorAuth
  alias HydraXWeb.Plugs.UserAuth

  action_fallback HydraXWeb.ProjectAPIFallbackController

  def register(conn, %{"email" => _email} = params) do
    case Accounts.register_first_operator(params) do
      {:ok, %{user: user}} ->
        conn
        |> OperatorAuth.log_in(user)
        |> put_status(:created)
        |> json(%{data: user_payload(user)})

      {:error, :registration_closed} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "registration_closed"})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email_required"})
  end

  def dev_login(conn, _params) do
    if DevAuth.enabled?() do
      user = DevAuth.operator_user!()

      conn
      |> OperatorAuth.log_in(user)
      |> json(%{data: user_payload(user)})
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "not_found"})
    end
  end

  def login(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    ip = client_ip(conn)
    throttle = LoginThrottle.state(ip)

    cond do
      throttle.rate_limited? ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited", retry_after: throttle.retry_after_seconds})

      true ->
        case Accounts.authenticate_user(email, password) do
          {:ok, user} ->
            LoginThrottle.clear_attempts(ip)

            conn =
              if Accounts.operator?(user) do
                OperatorAuth.log_in(conn, user)
              else
                UserAuth.put_user_session(conn, user)
              end

            json(conn, %{data: user_payload(user)})

          {:error, _reason} ->
            LoginThrottle.record_attempt(ip)

            conn
            |> put_status(:unauthorized)
            |> json(%{error: "invalid_credentials"})
        end
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email_and_password_required"})
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

  def forgot_password(conn, %{"email" => email}) when is_binary(email) do
    case Accounts.issue_password_reset(email) do
      {:ok, _token, raw_token} when is_binary(raw_token) ->
        Logger.warning(
          "Hydra local password reset requested for #{email}: #{url(~p"/password-reset/#{raw_token}")}"
        )

      _ ->
        :ok
    end

    json(conn, %{data: %{reset_requested: true}})
  end

  def forgot_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email_required"})
  end

  def reset_password(conn, %{"token" => token} = params) when is_binary(token) do
    password_params =
      params
      |> Map.take(["password", "password_confirmation"])

    case Accounts.reset_user_password(token, password_params) do
      {:ok, _user} ->
        json(conn, %{data: %{password_reset: true}})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, :invalid_or_expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_or_expired"})
    end
  end

  def reset_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "token_required"})
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

  defp user_payload(user) do
    %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      operator: Accounts.operator?(user),
      workspaces: Enum.map(Accounts.list_workspaces_for_user(user.id), &workspace_payload/1)
    }
  end

  defp workspace_payload(workspace) do
    %{id: workspace.id, name: workspace.name, slug: workspace.slug}
  end

  defp client_ip(conn) do
    forwarded = Plug.Conn.get_req_header(conn, "x-forwarded-for")

    case forwarded do
      [ip | _] -> ip |> String.split(",") |> List.first() |> String.trim()
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
