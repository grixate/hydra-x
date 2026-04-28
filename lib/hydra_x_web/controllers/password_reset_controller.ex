defmodule HydraXWeb.PasswordResetController do
  use HydraXWeb, :controller

  require Logger

  alias HydraX.Accounts

  def new(conn, _params) do
    render(conn, :new, form: to_form(%{}, as: :user))
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    case Accounts.issue_password_reset(email) do
      {:ok, _token, raw_token} when is_binary(raw_token) ->
        reset_url = url(~p"/password-reset/#{raw_token}")
        Logger.warning("Hydra local password reset requested for #{email}: #{reset_url}")

      _ ->
        :ok
    end

    conn
    |> put_flash(:info, "If that account exists, a reset link was created in the server logs.")
    |> redirect(to: ~p"/login")
  end

  def edit(conn, %{"token" => token}) do
    render(conn, :edit, token: token, form: to_form(%{}, as: :user))
  end

  def update(conn, %{"token" => token, "user" => params}) do
    case Accounts.reset_user_password(token, params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password updated. You can sign in now.")
        |> redirect(to: ~p"/login")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, token: token, form: to_form(changeset, as: :user))

      {:error, :invalid_or_expired} ->
        conn
        |> put_flash(:error, "Password reset link is invalid or expired.")
        |> redirect(to: ~p"/password-reset")
    end
  end
end
